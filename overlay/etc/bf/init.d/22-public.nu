use bf
bf env load

# Ensure the public directory exists and generate the maintenance page
def main [] {
    let public = bf env PROXY_PUBLIC

    # create the public directory with the default index file
    if ($public | bf fs is_not_dir) {
        bf write $"Creating ($public)."
        mkdir $public
        cp $"(bf env ETC_SRC)/index.html" $public
    }

    # generate the maintenance page
    bf write "Generating maintenance page."
    bf esh template $"($public)/maintenance.html"

    # return nothing
    return
}
