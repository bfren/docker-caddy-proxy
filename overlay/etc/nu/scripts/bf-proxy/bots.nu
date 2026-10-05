use bf

# Source of the list of AI crawlers - see https://github.com/ai-robots-txt/ai.robots.txt
export const robots_json_url = "https://raw.githubusercontent.com/ai-robots-txt/ai.robots.txt/{version}/robots.json"

# Categories used by ai.robots.txt for crawlers that collect training data
const training_categories = ["ai data scraper" "ai data scrapers"]

# Words in a crawler's 'function' that mean it collects training data
const training_pattern = '(?i)\b(train|trains|training|llms?|large language models?|language models?|datasets?|machine learning)\b'

# Phrases in a crawler's 'function' that mean it does NOT collect training data
const not_training_pattern = '(?i)not used for (model )?training'

# Returns true if a crawler from robots.json collects training data, based on its 'function'
export def is_training [
    robot: record   # A value from robots.json
]: nothing -> bool {
    let function = $robot
        | get --optional function
        | default ""
        | str trim
    if ($function =~ $not_training_pattern) { return false }
    ($function | str downcase) in $training_categories or ($function =~ $training_pattern)
}

# Select the user agents of crawlers that collect training data from the contents of robots.json
export def select_training [
    robots: record  # Parsed robots.json - keys are user agents
]: nothing -> list<string> {
    $robots
        | transpose agent robot
        | where {|x| is_training $x.robot }
        | get agent
        | sort --ignore-case
}

# Download robots.json, select training crawlers and save their user agents (one per line) to $path
export def download [
    version: string # ai.robots.txt release tag, e.g. v2.0
    path: string    # Where to save the list
]: nothing -> nothing {
    let url = bf string format $robots_json_url {version: $version}
    bf write $"Downloading AI crawler list from ($url)." bots/download
    let robots = try {
        http get --raw $url | from json
    } catch {
        bf write error $"Unable to download or parse ($url)." bots/download
    }

    let agents = select_training $robots
    if ($agents | is-empty) { bf write error "No AI training crawlers found." bots/download }

    $agents | str join (char newline) | save --force $path
    bf write $" .. saved ($agents | length) of ($robots | columns | length) crawlers to ($path)." bots/download
}

# Load the list of user agents to block (one per line, ignoring blank lines and # comments)
export def load [
    path: string    # Path to the list
]: nothing -> list<string> {
    if $path == "" or ($path | bf fs is_not_file) { return [] }
    open --raw $path
        | lines
        | each {|x| $x | str trim }
        | where {|x| $x != "" and not ($x | str starts-with "#") }
}

# Escape regular expression metacharacters in a user agent
export def escape []: string -> string {
    $in | str replace --all --regex '([\\.^$|?*+()\[\]{}])' '\$1'
}

# Build a case-insensitive regular expression matching any of the user agents at the start of a word
export def pattern [
    agents: list<string>    # User agents to match
]: nothing -> string {
    let escaped = $agents
        | each {|x| $x | escape }
        | str join "|"
    $"\(?i\)\\b\(($escaped)\)"
}
