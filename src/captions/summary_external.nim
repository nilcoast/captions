## External API summary generation (BYOK — Bring Your Own Key).
## Calls an OpenAI-compatible /chat/completions endpoint.

import std/[httpclient, json, strutils, logging, os]
import ./config

proc generateSummaryExternal*(cfg: ExternalSummaryConfig, prompt: string,
                               transcript: string): string =
  ## Call an OpenAI-compatible API to generate a summary.
  ## Returns the generated text, or empty string on failure.
  if cfg.apiKey == "":
    error "External summary API key not configured"
    return ""

  if cfg.apiUrl == "":
    error "External summary API URL not configured"
    return ""

  let apiKey = if cfg.apiKey.startsWith("env:"):
    getEnv(cfg.apiKey[4..^1])
  elif cfg.apiKey.startsWith("file:"):
    try:
      readFile(expandTilde(cfg.apiKey[5..^1])).strip()
    except IOError as e:
      error "Failed to read API key file: " & e.msg
      return ""
  else:
    cfg.apiKey

  if apiKey == "":
    error "External summary API key is empty"
    return ""

  let client = newHttpClient(timeout = 60_000)
  defer: client.close()
  client.headers = newHttpHeaders({
    "Content-Type": "application/json",
    "Authorization": "Bearer " & apiKey
  })

  let body = %*{
    "model": cfg.model,
    "messages": [
      {"role": "system", "content": prompt},
      {"role": "user", "content": transcript}
    ],
    "max_tokens": cfg.maxTokens,
    "temperature": 0.1
  }

  let url = cfg.apiUrl.strip(chars = {'/'}) & "/chat/completions"

  try:
    let resp = client.request(url, HttpPost, $body)
    if resp.code != Http200:
      error "External API returned " & $resp.code & ": " & resp.body
      return ""

    let json = parseJson(resp.body)
    result = json["choices"][0]["message"]["content"].getStr().strip()
  except CatchableError as e:
    error "External API request failed: " & e.msg
    return ""
