# Render .findings as a Markdown table. Everything that lands in a cell is
# text the API gave us, so it is escaped: a stray "|" would break the table
# and a "<" would let HTML through into a pull-request comment.
def clean: (. // "")
  | tostring
  | gsub("[\r\n\t]+"; " ")
  | gsub("<"; "&lt;")
  | gsub("\\|"; "\\|");

def dash: if . == "" then "—" else . end;

"| Package | Version | Ecosystem | Detail |",
"| --- | --- | --- | --- |",
((.[$section] // [])[]
  | "| `" + (.name | clean | dash)
  + "` | `" + (.version | clean | dash)
  + "` | " + (.ecosystem | clean | dash)
  + " | " + (.description | clean | dash)
  + " |")
