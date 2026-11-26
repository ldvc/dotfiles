#!/bin/bash
# Past 200k tokens every turn re-reads the whole context: ask Claude to suggest /clear at a task boundary. Fails open.

transcript=$(jq -r '.transcript_path // empty' 2>/dev/null)
[ -f "$transcript" ] || exit 0

# Transcripts reach tens of MB; the last main-chain turn sits in the tail. The cut first line fails fromjson and is skipped.
# A compact boundary resets the count: no usage is known until the next response.
tail -c 2000000 "$transcript" 2>/dev/null | jq -nRc '
  reduce (inputs | fromjson? | objects | select(.isSidechain != true)) as $e (null;
    if $e.type == "system" and $e.subtype == "compact_boundary" then null
    elif $e.type == "assistant" and ($e.message.usage | type) == "object" then $e.message.usage
    else . end)
  | (.input_tokens + .cache_read_input_tokens + .cache_creation_input_tokens) // 0
  | select(. >= 200000)
  | {hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext:
      "Context is \(. / 1000 | floor)k tokens. Every turn re-reads it. When a prompt starts a task unrelated to the previous one, the user wants a closing line suggesting /clear, unless they already declined."}}
' 2>/dev/null
exit 0
