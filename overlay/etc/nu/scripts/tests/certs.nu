use std assert
use ../bf-proxy/certs.nu *


#======================================================================================================================
# days_until
#======================================================================================================================

export def days_until__returns_whole_days [] {
    let date = (date now) + 10day + 1hr

    assert equal 10 (days_until $date)
}

export def days_until__is_negative_for_past_dates [] {
    let date = (date now) - 2day - 1hr

    assert equal (-3) (days_until $date)
}

export def days_until__accepts_strings [] {
    let date = (date now) + 5day + 1hr | format date "%Y-%m-%dT%H:%M:%SZ"

    assert equal 5 (days_until $date)
}


#======================================================================================================================
# display
#======================================================================================================================

export def display__sorts_by_expiry_and_sets_status [] {
    let certs = [
        {name: "ok.test", issuer: "Let's Encrypt R10", not_after: "2099-01-01T00:00:00Z", days_left: 30}
        {name: "expired.test", issuer: "Let's Encrypt R10", not_after: "2000-01-01T00:00:00Z", days_left: -1}
        {name: "soon.test", issuer: "Let's Encrypt R10", not_after: "2099-01-01T00:00:00Z", days_left: $warn_days}
    ]

    let result = display $certs

    assert equal ["expired.test" "soon.test" "ok.test"] ($result | get name)
    assert equal ["expired" "renew soon" "ok"] ($result | get status)
}
