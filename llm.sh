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

declare -a messages # array that holds conversation history

# Shift to get the query
# TODO make it so we don't have to enclose the query with quotes
shift $((OPTIND - 1))

# Join all arguments into a single query string
QUERY="$*"

# send prompt to openai api
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

# Start REPL-like environment
echo "Entering chat mode. Type 'exit' to quit."
#echo -e "\e[32m> ${QUERY} \e[0m"
while true; do
    read -p $'\e[32m> \e[0m' input

    if [[ "$input" == "exit" ]]; then
        break
    fi

    # add user message to history
    messages+=("$(jq --compact-output --null-input --arg content "$input" '{role: "user", content: $content}')")

    response=$(query_openai) # the response from OpenAI

    # add assistant message to history
    messages+=("$(jq --compact-output --null-input --arg content "$response" '{role: "assistant", content: $content}')")

    # Print the response
    echo -e "\e[34m"
    echo "$response"
    echo -e "\e[0m"
done
