# This file is a part of Julia. License is MIT: http://julialang.org/license

"""Mirror callback function

Function sets `+refs/*:refs/*` refspecs and `mirror` flag for remote reference.
"""
function mirror_callback(remote::Ptr{Ptr{Void}}, repo_ptr::Ptr{Void},
                         name::Cstring, url::Cstring, payload::Ptr{Void})
    # Create the remote with a mirroring url
    fetch_spec = "+refs/*:refs/*"
    err = ccall((:git_remote_create_with_fetchspec, :libgit2), Cint,
                (Ptr{Ptr{Void}}, Ptr{Void}, Cstring, Cstring, Cstring),
                remote, repo_ptr, name, url, fetch_spec)
    err != 0 && return Cint(err)

    # And set the configuration option to true for the push command
    config = GitConfig(GitRepo(repo_ptr,false))
    name_str = unsafe_string(name)
    err= try set!(config, "remote.$name_str.mirror", true)
         catch -1
         finally close(config)
         end
    err != 0 && return Cint(err)
    return Cint(0)
end

function authenticate_ssh(creds::SSHCredentials, libgit2credptr::Ptr{Ptr{Void}},
        username_ptr, protocol, host)
    isusedcreds = checkused!(creds)

    errcls, errmsg = Error.last_error()
    if errcls != Error.None
        # Check if we used ssh-agent
        if creds.usesshagent == "U"
            creds.usesshagent = "E" # reported ssh-agent error, disables ssh agent use for the future
        end
    end

    # first try ssh-agent if credentials support its usage
    if creds.usesshagent === nothing || creds.usesshagent == "Y" || creds.usesshagent == "U"
        err = ccall((:git_cred_ssh_key_from_agent, :libgit2), Cint,
                     (Ptr{Ptr{Void}}, Cstring), libgit2credptr, username_ptr)
        creds.usesshagent = "U" # used ssh-agent only one time
        err == 0 && return Cint(0)
    end

    if creds.prompt_if_incorrect
        # if username is not provided, then prompt for it
        username = if username_ptr == Cstring(C_NULL)
            uname = creds.user # check if credentials were already used
            !isusedcreds ? uname : prompt("Username for '$protocol://$host'", default=uname)
        else
            unsafe_string(username_ptr)
        end
        isempty(username) && return Cint(Error.EAUTH)

        # For SSH we need a private key location
        privatekey = if haskey(ENV,"SSH_KEY_PATH")
            ENV["SSH_KEY_PATH"]
        else
            keydefpath = creds.prvkey # check if credentials were already used
            keydefpath === nothing && (keydefpath = "")
            if isempty(keydefpath) || isusedcreds
                defaultkeydefpath = joinpath(homedir(),".ssh","id_rsa")
                if isempty(keydefpath) && isfile(defaultkeydefpath)
                    keydefpath = defaultkeydefpath
                else
                    keydefpath =
                        prompt("Private key location for '$protocol://$username@$host'", default=keydefpath)
                end
            end
            keydefpath
        end

        # If the private key changed, invalidate the cached public key
        (privatekey != creds.prvkey) &&
            (creds.pubkey = "")

        # For SSH we need a public key location, look for environment vars SSH_* as well
        publickey = if haskey(ENV,"SSH_PUB_KEY_PATH")
            ENV["SSH_PUB_KEY_PATH"]
        else
            keydefpath = creds.pubkey # check if credentials were already used
            keydefpath === nothing && (keydefpath = "")
            if isempty(keydefpath) || isusedcreds
                if isempty(keydefpath)
                    keydefpath = privatekey*".pub"
                end
                if !isfile(keydefpath)
                    prompt("Public key location for '$protocol://$username@$host'", default=keydefpath)
                end
            end
            keydefpath
        end

        passphrase_required = true
        if !isfile(privatekey)
            warn("Private key not found")
        else
            # In encrypted private keys, the second line is "Proc-Type: 4,ENCRYPTED"
            open(privatekey) do f
                readline(f)
                passphrase_required = readline(f) == "Proc-Type: 4,ENCRYPTED"
            end
        end

        passphrase = if haskey(ENV,"SSH_KEY_PASS")
            ENV["SSH_KEY_PASS"]
        else
            passdef = creds.pass # check if credentials were already used
            passdef === nothing && (passdef = "")
            if passphrase_required && (isempty(passdef) || isusedcreds)
                if is_windows()
                    passdef = Base.winprompt(
                        "Your SSH Key requires a password, please enter it now:",
                        "Passphrase required", privatekey; prompt_username = false)
                    isnull(passdef) && return Cint(Error.EAUTH)
                    passdef = Base.get(passdef)[2]
                else
                    passdef = prompt("Passphrase for $privatekey", password=true)
                end
            end
            passdef
        end
        ((creds.user != username) || (creds.pass != passphrase) ||
            (creds.prvkey != privatekey) || (creds.pubkey != publickey)) && reset!(creds)

        creds.user = username # save credentials
        creds.prvkey = privatekey # save credentials
        creds.pubkey = publickey # save credentials
        creds.pass = passphrase
    else
        isusedcreds && return Cint(Error.EAUTH)
    end

    err = ccall((:git_cred_ssh_key_new, :libgit2), Cint,
                 (Ptr{Ptr{Void}}, Cstring, Cstring, Cstring, Cstring),
                 libgit2credptr, creds.user, creds.pubkey, creds.prvkey, creds.pass)
    return err
end

function authenticate_userpass(creds::UserPasswordCredentials, libgit2credptr::Ptr{Ptr{Void}},
        protocol, host, urlusername)
    isusedcreds = checkused!(creds)

    errcls, errmsg = Error.last_error()
    if errcls != Error.None
        # Check if we used ssh-agent
        if creds.use_credential_helper == 'U'
            creds.use_credential_helper = 'E' # disables git-credentials use in the future
        end
    end

    username = creds.user !== nothing ? creds.user : ""
    userpass = creds.pass !== nothing ? creds.pass : ""
    assigned = false

    # first try git-credentials if credentials support its usage
    if creds.use_credential_helper in ('Y', 'U')
        config = LibGit2.GitConfig()  # TODO: Not right

        cred = Credential(protocol, host, "", urlusername, "")
        @show cred
        helpers = helpers!(config, cred)
        fill!(helpers, cred)

        @show cred

        if filled(cred)
            username = cred.username
            userpass = cred.password
            assigned = true
        end

        creds.use_credential_helper = 'U'  # used git-credentials only one time
    end

    if !assigned && creds.prompt_if_incorrect
        if is_windows()
            if isempty(username) || isempty(userpass) || isusedcreds
                res = Base.winprompt("Please enter your credentials for '$protocol://$host'", "Credentials required",
                        username === nothing || isempty(username) ?
                        urlusername : username; prompt_username = true)
                isnull(res) && return Cint(Error.EAUTH)
                username, userpass = Base.get(res)
            end
        elseif isusedcreds
            username = prompt("Username for '$protocol://$host'", default = isempty(username) ?
                urlusername : username)
            userpass = prompt("Password for '$protocol://$username@$host'", password=true)
        end
        ((creds.user != username) || (creds.pass != userpass)) && reset!(creds)
        creds.user = username # save credentials
        creds.pass = userpass # save credentials

        isempty(username) && isempty(userpass) && return Cint(Error.EAUTH)
    elseif !assigned
        isusedcreds && return Cint(Error.EAUTH)
    end

    err = ccall((:git_cred_userpass_plaintext_new, :libgit2), Cint,
                 (Ptr{Ptr{Void}}, Cstring, Cstring),
                 libgit2credptr, username, userpass)
    err == 0 && return Cint(0)
end


"""Credentials callback function

Function provides different credential acquisition functionality w.r.t. a connection protocol.
If a payload is provided then `payload_ptr` should contain a `LibGit2.AbstractCredentials` object.

For `LibGit2.Consts.CREDTYPE_USERPASS_PLAINTEXT` type, if the payload contains fields:
`user` & `pass`, they are used to create authentication credentials.
Empty `user` name and `pass`word trigger an authentication error.

For `LibGit2.Consts.CREDTYPE_SSH_KEY` type, if the payload contains fields:
`user`, `prvkey`, `pubkey` & `pass`, they are used to create authentication credentials.
Empty `user` name triggers an authentication error.

Credentials are checked in the following order (if supported):
- ssh key pair (`ssh-agent` if specified in payload's `usesshagent` field)
- plain text

**Note**: Due to the specifics of the `libgit2` authentication procedure, when
authentication fails, this function is called again without any indication whether
authentication was successful or not. To avoid an infinite loop from repeatedly
using the same faulty credentials, the `checkused!` function can be called. This
function returns `true` if the credentials were used.
Using credentials triggers a user prompt for (re)entering required information.
`UserPasswordCredentials` and `CachedCredentials` are implemented using a call
counting strategy that prevents repeated usage of faulty credentials.
"""
function credentials_callback(libgit2credptr::Ptr{Ptr{Void}}, url_ptr::Cstring,
                              username_ptr::Cstring,
                              allowed_types::Cuint, payload_ptr::Ptr{Void})
    err = 0
    url = unsafe_string(url_ptr)

    # parse url for protocol and host
    urlparts = match(URL_REGEX, url)
    protocol = urlparts[:protocol] === nothing ? "" : urlparts[:protocol]
    urlusername = urlparts[:user] === nothing ? "" : urlparts[:user]
    host = urlparts[:host]

    # get credentials object from payload pointer
    @assert payload_ptr != C_NULL
    creds = unsafe_pointer_to_objref(payload_ptr)
    explicit = !isnull(creds[]) && !isa(Base.get(creds[]), CachedCredentials)
    # use ssh key or ssh-agent
    if isset(allowed_types, Cuint(Consts.CREDTYPE_SSH_KEY))
        sshcreds = get_creds!(creds, "ssh://$host", reset!(SSHCredentials(true), -1))
        if isa(sshcreds, SSHCredentials)
            err = authenticate_ssh(sshcreds, libgit2credptr, username_ptr, protocol, host)
            err == 0 && return err
        end
    end

    if isset(allowed_types, Cuint(Consts.CREDTYPE_USERPASS_PLAINTEXT))
        defaultcreds = reset!(UserPasswordCredentials(true), -1)
        credid = "$protocol://$host"
        upcreds = get_creds!(creds, credid, defaultcreds)
        # If there were stored SSH credentials, but we ended up here that must
        # mean that something went wrong. Replace the SSH credentials by user/pass
        # credentials
        if !isa(upcreds, UserPasswordCredentials)
            upcreds = defaultcreds
            isa(Base.get(creds[]), CachedCredentials) && (Base.get(creds[]).creds[credid] = upcreds)
        end
        return authenticate_userpass(upcreds, libgit2credptr, protocol, host, urlusername)
    end

    # No authentication method we support succeeded. The most likely cause is
    # that explicit credentials were passed in, but said credentials are incompatible
    # with the remote host.
    if err == 0
        if explicit
            warn("The explicitly provided credentials were incompatible with " *
                 "the server's supported authentication methods")
        end
        err = Cint(Error.EAUTH)
    end
    return Cint(err)
end

function fetchhead_foreach_callback(ref_name::Cstring, remote_url::Cstring,
                        oid::Ptr{GitHash}, is_merge::Cuint, payload::Ptr{Void})
    fhead_vec = unsafe_pointer_to_objref(payload)::Vector{FetchHead}
    push!(fhead_vec, FetchHead(unsafe_string(ref_name), unsafe_string(remote_url), GitHash(oid), is_merge == 1))
    return Cint(0)
end

"C function pointer for `mirror_callback`"
mirror_cb() = cfunction(mirror_callback, Cint, (Ptr{Ptr{Void}}, Ptr{Void}, Cstring, Cstring, Ptr{Void}))
"C function pointer for `credentials_callback`"
credentials_cb() = cfunction(credentials_callback, Cint, (Ptr{Ptr{Void}}, Cstring, Cstring, Cuint, Ptr{Void}))
"C function pointer for `fetchhead_foreach_callback`"
fetchhead_foreach_cb() = cfunction(fetchhead_foreach_callback, Cint, (Cstring, Cstring, Ptr{GitHash}, Cuint, Ptr{Void}))
