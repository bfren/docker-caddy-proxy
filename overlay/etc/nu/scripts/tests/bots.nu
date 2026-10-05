use std assert
use ../bf-proxy bots *


#======================================================================================================================
# is_training
#======================================================================================================================

export def is_training__true_for_data_scraper_category [] {
    assert (is_training {function: "AI Data Scrapers"})
    assert (is_training {function: "AI data scraper"})
}

export def is_training__true_when_function_mentions_training [] {
    assert (is_training {function: "Scrapes data to train OpenAI's products."})
    assert (is_training {function: "LLM training."})
    assert (is_training {function: "Content is used to train open language models."})
    assert (is_training {function: "Provides open crawl dataset, used for many purposes, including Machine Learning/AI."})
}

export def is_training__false_for_search_assistants_and_agents [] {
    assert not (is_training {function: "AI Search Crawlers"})
    assert not (is_training {function: "AI Assistants"})
    assert not (is_training {function: "AI Agents"})
    assert not (is_training {function: "Search result generation."})
    assert not (is_training {function: "Retrieves data to provide responses to user-initiated prompts."})
}

export def is_training__false_when_function_says_not_used_for_training [] {
    assert not (is_training {function: "Indexes web content for search. Per Mistral, not used for model training."})
}

export def is_training__false_when_function_missing [] {
    assert not (is_training {})
}


#======================================================================================================================
# select_training
#======================================================================================================================

export def select_training__returns_sorted_training_agents [] {
    let robots = {
        GPTBot: {function: "Scrapes data to train OpenAI's products."}
        "OAI-SearchBot": {function: "Search result generation."}
        CCBot: {function: "AI Data Scrapers"}
        "ChatGPT-User": {function: "AI Assistants"}
    }

    let result = select_training $robots

    assert equal ["CCBot" "GPTBot"] $result
}


#======================================================================================================================
# load
#======================================================================================================================

export def load__ignores_blank_lines_and_comments [] {
    let path = mktemp
    "# comment\nGPTBot\n\n  CCBot  \n" | save --force $path

    let result = load $path

    assert equal ["GPTBot" "CCBot"] $result
}

export def load__returns_empty_list_when_file_does_not_exist [] {
    assert equal [] (load "/tmp/does-not-exist.txt")
    assert equal [] (load "")
}


#======================================================================================================================
# escape / pattern
#======================================================================================================================

export def escape__escapes_regex_metacharacters [] {
    assert equal 'Brightbot 1\.0' ("Brightbot 1.0" | escape)
    assert equal 'iaskspider/2\.0' ("iaskspider/2.0" | escape)
    assert equal 'a\(b\)\+\*\?' ("a(b)+*?" | escape)
}

export def pattern__matches_listed_agents_case_insensitively [] {
    let p = pattern ["GPTBot" "Brightbot 1.0"]

    assert ("Mozilla/5.0 (compatible; GPTBot/1.2; +https://openai.com/gptbot)" =~ $p)
    assert ("brightbot 1.0" =~ $p)
}

export def pattern__does_not_match_other_agents [] {
    let p = pattern ["GPTBot" "Brightbot 1.0" "Spider"]

    assert not ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0" =~ $p)
    assert not ("Brightbot 1x0" =~ $p)
    assert not ("Baiduspider/2.0" =~ $p)
}
