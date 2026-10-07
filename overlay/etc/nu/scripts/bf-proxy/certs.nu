use bf

# Certificates expiring within this many days are flagged - Caddy normally renews when a third of the lifetime remains
export const warn_days = 14

# List the certificates in Caddy's storage, with the number of days until each one expires
export def main [
    storage: string # Caddy storage directory
]: nothing -> table {
    let certs = { ^certinfo $storage } | bf handle certs | from json
    $certs | each {|c| $c | insert days_left (days_until $c.not_after) }
}

# Return the number of whole days from now until $date (negative if $date has passed)
export def days_until [
    date: any   # Date (or date string)
]: nothing -> int {
    ($date | into datetime) - (date now) | $in / 1day | math floor
}

# Format the certificate list for display
export def display [
    certs: table    # Certificates from main
]: nothing -> table {
    let get_status = {|days_left|
        if $days_left < 0 {
             "expired"
        } else if $days_left <= $warn_days {
            "renew soon"
        } else {
            "ok"
        }
    }
    $certs
        | sort-by days_left
        | each {|c|
            {
                name: $c.name
                issuer: $c.issuer
                expires: ($c.not_after | into datetime | format date "%Y-%m-%d %H:%M")
                days_left: $c.days_left
                status: ($c.days_left | $get_status)
            }
        }
}
