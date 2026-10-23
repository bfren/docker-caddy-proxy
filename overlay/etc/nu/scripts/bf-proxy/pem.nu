use bf
use certs.nu
use conf.nu
use renew.nu [storage_name]

# Write a PEM file (private key followed by the full chain) for each certificate in Caddy's storage, for use by other
# containers (e.g. vsftpd in bfren/ftps) - returns the paths of the files that were written
#
# Files are only written when their contents change, and are written in place so a single file bind-mounted into
# another container (which follows the original inode) sees the new certificate
export def main [
    storage: string # Caddy storage directory
    dir: string     # Directory to write PEM files to, as <dir>/<host>/<host>.pem
]: nothing -> list<string> {
    certs $storage | latest | each {|c| write (file $dir $c.name) (contents $c.path) } | compact
}

# Create missing empty PEM files, write changed PEM files, and log each one
export def sync [
    storage: string         # Caddy storage directory
    dir: string             # Directory to write PEM files to
    hosts: list<string>     # Host names to create empty PEM files for
]: nothing -> nothing {
    placeholders $dir $hosts | each {|x| bf write $"Created empty ($x) - it will be written when the certificate is obtained." pem }
    main $storage $dir | each {|x| bf write ok $"Written ($x)." pem }

    # return nothing
    return
}

# Return every host name in the configuration, including the proxy domain
export def conf_hosts [
    config: record  # Configuration from conf read
]: nothing -> list<string> {
    [$config.opts.proxy_domain] | append ($config.domains | each {|d| conf hosts $d } | flatten) | uniq
}

# Create an empty PEM file for each host name that does not have one yet, so a container that bind-mounts the file can
# start before the certificate is obtained (otherwise Docker creates a directory) - returns the paths created
export def placeholders [
    dir: string             # Directory containing PEM files
    hosts: list<string>     # Host names
]: nothing -> list<string> {
    $hosts
        | each {|h| file $dir (storage_name $h) }
        | uniq
        | where {|p| not ($p | path exists) }
        | each {|p| save_pem $p "" ; $p }
}

# Return the certificate to use for each host name: the one that expires last, if Caddy has more than one
# (e.g. staging and live certificates for the same host name)
export def latest []: table -> table {
    sort-by not_after --reverse | uniq-by name
}

# Return the path of the PEM file for a host name (wildcards use Caddy's storage name, e.g. wildcard_.example.com)
export def file [
    dir: string     # Directory containing PEM files
    name: string    # Host name, as stored by Caddy
]: nothing -> string {
    $"($dir)/($name)/($name).pem"
}

# Return the PEM contents for a certificate: its private key followed by the full chain
export def contents [
    crt: string     # Path to the certificate (the private key has the same name with a .key extension)
]: nothing -> string {
    let key = $crt | str replace --regex '\.crt$' '.key'
    [$key $crt] | each {|x| open --raw $x | str trim } | str join (char newline) | $"($in)(char newline)"
}

# Write $contents to $pem if it has changed, returning $pem if it was written (or null if not)
export def write [
    pem: string         # Path to the PEM file
    contents: string    # PEM contents
]: nothing -> any {
    # Docker creates a directory if a bind-mounted file does not exist when a container starts
    if ($pem | path type) == "dir" {
        bf write notok $"($pem) is a directory - remove it and restart any container that mounts it." pem
        return
    }

    if ($pem | path exists) and (open --raw $pem) == $contents { return }

    save_pem $pem $contents
    $pem
}

# Save $contents to $pem, creating its directory, and set ownership and permissions to match the rest of /ssl
export def save_pem [
    pem: string         # Path to the PEM file
    contents: string    # PEM contents
]: nothing -> nothing {
    let parent = $pem | path dirname
    mkdir $parent
    bf ch --owner www:www --mode 0700 $parent

    # save truncates and rewrites an existing file, keeping its inode
    $contents | save --force $pem
    bf ch --owner www:www --mode 0600 $pem
}
