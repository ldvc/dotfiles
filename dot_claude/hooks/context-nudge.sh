#!/bin/bash
# Past 120k tokens, or after git push or a Jira comment, ask Claude to suggest /clear at a task boundary. Fails open.

transcript=$(jq -r '.transcript_path // empty' 2>/dev/null)
[ -f "$transcript" ] || exit 0

# Transcripts reach tens of MB; the last main-chain turn sits in the tail. The cut first line fails fromjson and is skipped.
# A compact boundary resets the count: no usage is known until the next response.
# A prompt resets the boundary flag only at the next assistant entry, so the result is the same whether the new prompt is logged yet.
tail -c 2000000 "$transcript" 2>/dev/null | jq -nRc '
  reduce (inputs | fromjson? | objects | select(.isSidechain != true)) as $e ({};
    if $e.type == "system" and $e.subtype == "compact_boundary" then {}
    elif $e.type == "user" and $e.isMeta != true and ($e.origin.kind? // null) != "task-notification"
      and ($e.message.content | type == "string" or (type == "array" and all(.[]; .type? != "tool_result")))
    then .prompt = true
    elif $e.type == "assistant" then
      (if .prompt then .prompt = false | .boundary = false else . end)
      | if ($e.message.usage | type) == "object" then .usage = $e.message.usage else . end
      | if any($e.message.content[]? | objects | select(.type == "tool_use" and .name == "Bash") | .input.command? | strings;
          test("\\bgit\\s+(-C\\s+\\S+\\s+)?push\\b|\\bjira\\s+issue\\s+comment\\s+add\\b"))
        then .boundary = true else . end
    else . end)
  | ((.usage.input_tokens + .usage.cache_read_input_tokens + .usage.cache_creation_input_tokens) // 0) as $tokens
  | if $tokens >= 120000 then
      "Context is \($tokens / 1000 | floor)k tokens. Every turn re-reads it. When a prompt starts a task unrelated to the previous one, the user wants a closing line suggesting /clear, unless they already declined."
    elif .boundary then
      "The previous turn ran git push or posted a Jira comment, which usually ends a task. Context is \($tokens / 1000 | floor)k tokens. When a prompt starts a task unrelated to the previous one, the user wants a closing line suggesting /clear, unless they already declined."
    else empty end
  | {hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: .}}
' 2>/dev/null
exit 0
