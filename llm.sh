#!/bin/bash

# Default values
API_ENDPOINT="https://api.openai.com/v1/chat/completions"
MODEL="gpt-3.5-turbo"

# check cli arguments
USAGE_STRING="Usage: llm [-e api_endpoint] [-m model] [-t api_token] <query>"
while getopts "e:m:t:" opt; do
    case $opt in
        e) API_ENDPOINT="$OPTARG" ;;
        m) MODEL="$OPTARG" ;;
        t) API_TOKEN="$OPTARG" ;;
        *) echo "$USAGE_STRING"; exit 1 ;;
    esac
done

# get api token from envar if it exists
if [ -z "$API_TOKEN" ]; then
    if [ -z "$OPENAI_API_KEY" ]; then
        echo "Set OPENAI_API_KEY environment variable or pass it with -t <api_token>"
        exit 1
    else
        API_TOKEN="$OPENAI_API_KEY"
    fi
fi

# send prompt to openai api w/o streaming (NOTE: deprecated)
function query_openai() {
  local json_messages=$(printf '%s\n' "${messages[@]}" | jq -c -s .)
  local response=$(curl -s -X POST "$API_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_TOKEN" \
    -d '{
      "model": "'"$MODEL"'",
      "messages": '"$json_messages"',
      "max_tokens": 2048
    }' | jq -r '.choices[0].message.content')
  echo "$response"
}

# streamed openai query using curl & temp files
function query_openai_streamed() {
    local json_messages=$(printf '%s\n' "${messages[@]}" | jq -c -s .)
    curl --silent -X POST "$API_ENDPOINT" \
        -H "Authorization: Bearer $API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$MODEL"'",
            "messages": '"$json_messages"',
              "stream": true
              }' --no-buffer > "$temp_file" &
    curl_pid=$! # store curl command PID


    while kill -0 "$curl_pid" 2>/dev/null; do # curl is still processing
        # Read the new lines from the temporary file
        # TODO don't reread old lines, keep track of which line was read last
        while IFS= read -r line; do
            # Check if the line starts with "data: "
            if [[ $line == data:* ]]; then

                json_data="${line:6}" # remove "data: " prefix

                # Check if API has finished
                finish_reason=$(printf '%s' "$json_data" | jq --raw-output '.choices[0].finish_reason // empty')
                if [[ "$finish_reason" != "eos" ]]; then
                    # Print the content if it exists NOTE: the sed replacements are a workaround to preserve newlines
                    # (i.e. "content" : "\n") in the output, since jq --raw-output seems to remove them
                    content=$(printf '%s' "$json_data" | jq '.choices[0].delta.content // empty' | sed 's/^.//' | sed 's/.$//' | sed 's/\\"/"/g')
                    if [[ -n $content ]]; then
                        echo -ne "$content"  # print out response chunk
                        response+="$content" # add to array
                        sleep 0.05 # TODO only needed because we may reread old lines
                    fi
                else
                    break 2
                fi
            fi
        done < "$temp_file"
    done

    > "$temp_file" # clear out temp file
}

declare -a messages # array that holds conversation history
temp_file=$(mktemp) # stores streamed-in response
cleanup() {
    rm -f "$temp_file"
    exit
}
trap cleanup INT  # delete temp file on Ctrl-C
trap cleanup EXIT # delete temp file on exit

# TODO support <query> argument
# TODO make it so we don't have to enclose the query with quotes
shift $((OPTIND - 1)) # Shift to get the query
QUERY="$*"            # Join all arguments into a single query string

# Start REPL-like environment
echo "Entering chat mode. Type 'exit' to quit."
#echo -e "\e[32m> ${QUERY} \e[0m"
while true; do
    # TODO support input with linebreaks
    read -p $'\e[32m> \e[0m' input

    if [[ "$input" == "exit" ]]; then
        break
    fi

    # add user message to history
    messages+=("$(jq --compact-output --null-input --arg content "$input" '{role: "user", content: $content}')")

    echo -e "\e[34m" # color response blue
    query_openai_streamed
    echo -e "\e[0m"

    # add assistant message to history
    messages+=("$(jq --compact-output --null-input --arg content "$response" '{role: "assistant", content: $content}')")
done
