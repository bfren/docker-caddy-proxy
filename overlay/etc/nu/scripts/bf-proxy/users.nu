use bf

# Add (or replace) a user for HTTP basic authentication, storing a bcrypt hash of the password
export def add [
    username: string    # The user name
    password: string    # The password (will be hashed)
]: nothing -> nothing {
    let path = bf env PROXY_USERS
    let hash = { ^caddy hash-password --plaintext $password } | bf handle users/add

    let users = if ($path | path exists) { open --raw $path | from json } else { {} }
    $users | upsert $username $hash | to json --indent 4 | save --force $path
    bf write ok $"User ($username) saved to ($path)." users/add
}

# Remove a user
export def remove [
    username: string    # The user name
]: nothing -> nothing {
    let path = bf env PROXY_USERS
    if not ($path | path exists) { bf write error $"($path) does not exist." users/remove }

    let users = open --raw $path | from json
    if $username not-in ($users | columns) { bf write error $"User ($username) does not exist." users/remove }
    $users | reject $username | to json --indent 4 | save --force $path
    bf write ok $"User ($username) removed." users/remove
}
