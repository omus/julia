const CREDENTIAL_URL_REGEX = r"^(?<proto>.+?)://(?:(?<user>.+?)(?:\:(?<pass>.+?))?\@)?(?<host>[^/]+)(?<path>/.*)?$"

type Credential
    protocol::String
    host::String
    path::String
    username::String
    password::String
    helpers::Array{String}
end

function Credential(protocol::AbstractString, host::AbstractString, path::AbstractString, username::AbstractString, password::AbstractString)
    Credential(protocol, host, path, username, password, String[])
end

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
    while !eof(io)
        key, value = split(readline(io), '=')

        if key == "protocol"
            cred.protocol = value
        elseif key == "host"
            cred.host = value
        elseif key == "path"
            cred.path = vale
        elseif key == "username"
            cred.username = value
        elseif key == "password"
            cred.password = value
        end
    end

    return cred
end

read(io::IO, ::Type{Credential}) = read!(io, Credential())

function credential_do!(cred::Credential, helper::AbstractString, operation::AbstractString)
    if startswith(helper, "!")
        cmd_str = helper[2:end]
    elseif isabspath(first(Base.shell_split(helper)))
        cmd_str = helper
    else
        cmd_str = "git credential-$helper"
    end

    cmd = `$(Base.shell_split(cmd_str)...) $operation`
    return run_credential_helper!(cred, cmd)
end

function run_credential_helper!(cred::Credential, cmd::Cmd)
    println("CMD: $cmd")
    output, input, p = readandwrite(cmd)
    write(input, cred)
    write(input, "\n")
    close(input)

    read!(output, cred)
    close(output)

    return cred
end

function helpers!(cfg::LibGit2.GitConfig, cred::Credential)
    # Note: Should be quoting user input but `\Q` and `\E` isn't supported by libgit2
    # ci = LibGit2.GitConfigIter(cfg, Regex("credential(\\.$protocol://$host)?\\.helper"))

    for entry in LibGit2.GitConfigIter(cfg, r"credential.*")
        name, value = unsafe_string(entry.name), unsafe_string(entry.value)

        a, b = search(name, '.'), rsearch(name, '.')
        url = SubString(name, a + 1, b - 1)
        token = SubString(name, b + 1)

        if !isempty(url)
            want = parse(Credential, url)
            !credential_match(want, cred) && continue
        end

        if token == "helper"
            push!(cred.helpers, value)
        elseif token == "username"
            if isempty(cred.username)
                cred.username = value
            end
        end
    end
end

function credential_fill!(cred::Credential)
    if !isempty(cred.username) && !isempty(cred.password)
        return
    end

    # TODO
    # if isempty(cred.helpers)
    #     helpers!(cfg, cred)
    # end

    for helper in cred.helpers
        credential_do!(cred, helper, "get")

        if !isempty(cred.username) && !isempty(cred.password)
            return cred
        end
    end

    return cred
end
