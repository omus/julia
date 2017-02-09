const CREDENTIAL_URL_REGEX = r"^(?<proto>.+?)://(?:(?<user>.+?)(?:\:(?<pass>.+?))?\@)?(?<host>[^/]+)(?<path>/.*)?$"

type CredentialHelper
    cmd::Cmd
end

type Credential
    protocol::String
    host::String
    path::String
    username::String
    password::String
end

function Base.parse(::Type{CredentialHelper}, helper::AbstractString)
    if startswith(helper, "!")
        cmd_str = helper[2:end]
    elseif isabspath(first(Base.shell_split(helper)))
        cmd_str = helper
    else
        cmd_str = "git credential-$helper"
    end

    CredentialHelper(`$(Base.shell_split(cmd_str)...)`)
end

function run!(helper::CredentialHelper, operation::AbstractString, cred::Credential)
    cmd = `$(helper.cmd) $operation`
    println("CMD: $cmd")
    output, input, p = readandwrite(cmd)

    # Provide the helper with the credential information we know
    write(input, cred)
    write(input, "\n")
    close(input)

    # Process the response from the helper
    read!(output, cred)
    close(output)

    return cred
end

function run(helper::CredentialHelper, operation::AbstractString, cred::Credential)
    updated_cred = deepcopy(cred)
    run!(helper, operation, updated_cred)
end

# function Credential(protocol::AbstractString, host::AbstractString, path::AbstractString, username::AbstractString, password::AbstractString)
#     Credential(protocol, host, path, username, password)
# end

Credential() = Credential("", "", "", "", "")

function Base.parse(::Type{Credential}, url::AbstractString)
    # TODO: It appears that the Git internals expect the contents to be URL encoded:
    # https://github.com/git/git/blob/24321375cda79f141be72d1a842e930df6f41725/credential.c#L324
    #
    # Match one of:
    # (1) proto://<host>/...
    # (2) proto://<user>@<host>/...
    # (3) proto://<user>:<pass>@<host>/...
    m = match(CREDENTIAL_URL_REGEX, url)
    m === nothing && error("Unable to parse URL")
    return Credential(
        m[:proto],
        m[:host],
        m[:path] == nothing ? "" : m[:path],
        m[:user] == nothing ? "" : m[:user],
        m[:pass] == nothing ? "" : m[:pass],
    )
end

function merge!(a::Credential, b::Credential)
    !isempty(b.protocol) && (a.protocol = b.protocol)
    !isempty(b.host) && (a.host = b.host)
    !isempty(b.path) && (a.path = b.path)
    !isempty(b.username) && (a.username = b.username)
    !isempty(b.password) && (a.password = b.password)
end

function Base.:(==)(a::Credential, b::Credential)
    return (
        a.protocol == b.protocol &&
        a.host == b.host &&
        a.path == b.path &&
        a.username == b.username &&
        a.password == b.password
    )
end

function credential_match(want::Credential, have::Credential)
    check(x, y) = isempty(x) || (!isempty(y) && x == y)
    return (
        check(want.protocol, have.protocol) &&
        check(want.host, have.host) &&
        check(want.path, have.path) &&
        check(want.username, have.username)
    )
end

function Base.write(io::IO, cred::Credential)
    !isempty(cred.protocol) && println(io, "protocol=", cred.protocol)
    !isempty(cred.host) && println(io, "host=", cred.host)
    !isempty(cred.path) && println(io, "path=", cred.path)
    !isempty(cred.username) && println(io, "username=", cred.username)
    !isempty(cred.password) && println(io, "password=", cred.password)
    nothing
end

function read!(io::IO, cred::Credential)
    # https://git-scm.com/docs/git-credential#IOFMT
    while !eof(io)
        key, value = split(readline(io), '=')

        if key == "protocol"
            cred.protocol = value
        elseif key == "host"
            cred.host = value
        elseif key == "path"
            cred.path = value
        elseif key == "username"
            cred.username = value
        elseif key == "password"
            cred.password = value
        elseif key == "url"
            merge!(cred, parse(Credential, value))
        end
    end

    return cred
end

read(io::IO, ::Type{Credential}) = read!(io, Credential())

"""
Credential helpers that are relevant to the given credentials. If the credentials do not
contain a username one may be added at this step by the configuration.
"""
function helpers!(cfg::LibGit2.GitConfig, cred::Credential)
    # Note: Should be quoting user input but `\Q` and `\E` isn't supported by libgit2
    # ci = LibGit2.GitConfigIter(cfg, Regex("credential(\\.$protocol://$host)?\\.helper"))

    # Note: We will emulate the way Git reads the the configuration file which is from
    # top to bottom with no precedence on specificity.
    helpers = CredentialHelper[]
    for entry in LibGit2.GitConfigIter(cfg, r"credential.*")
        name, value = unsafe_string(entry.name), unsafe_string(entry.value)

        a, b = search(name, '.'), rsearch(name, '.')
        url = SubString(name, a + 1, b - 1)
        token = SubString(name, b + 1)

        if !isempty(url)
            want = parse(Credential, url)
            !credential_match(want, cred) && continue
        end

        println("CONFIG: $name = $value")

        if token == "helper"
            push!(helpers, parse(CredentialHelper, value))
        elseif token == "username"
            if isempty(cred.username)
                cred.username = value
            end
        end
    end

    return helpers
end

function filled(cred::Credential)
    !isempty(cred.username) && !isempty(cred.password)
end

function fill!(helpers::AbstractArray{CredentialHelper}, cred::Credential)
    filled(cred) && return cred
    for helper in helpers
        run!(helper, "store", cred)
        filled(cred) && break
    end
    return cred
end

function fill(helpers::AbstractArray{CredentialHelper}, cred::Credential)
    new_cred = deepcopy(cred)
    fill!(helpers, new_cred)
end

function approve(helpers::AbstractArray{CredentialHelper}, cred::Credential)
    !filled(cred) && error("Credentials are not filled")
    for helper in helpers
        run(helper, "store", cred)
    end
end

function reject(helpers::AbstractArray{CredentialHelper}, cred::Credential)
    !filled(cred) && return

    for helper in helpers
        run(helper, "erase", cred)
    end

    Base.securezero!(cred.username)
    Base.securezero!(cred.password)
    cred.username = ""
    cred.password = ""
    nothing
end
