defmodule ExDNA.Reporter.HTML do
  @moduledoc """
  Generates a self-contained HTML report file for clone detection results.

  Writes `ex_dna_report.html` to the current directory.
  """

  @behaviour ExDNA.Reporter

  @output_file "ex_dna_report.html"

  require EEx

  EEx.function_from_file(:defp, :render_template, Path.join(__DIR__, "html.html.eex"), [
    :clones,
    :stats
  ])

  @impl true
  def report(%ExDNA.Report{clones: clones, stats: stats, config: config}) do
    output_file = config.output_file || @output_file
    html = render_template(clones, stats)
    File.write!(output_file, html)
    IO.puts("  HTML report written to #{output_file}")
    :ok
  end

  defp render_suggestion(nil), do: ""

  defp render_suggestion(%{kind: :extract_function} = s) do
    params = Enum.join(s.params, ", ")

    call_sites =
      Enum.map_join(s.call_sites, "\n", fn site ->
        ~s(<div class="call-site">#{escape(Path.relative_to_cwd(site.file))}:#{site.line} → <code>#{escape(site.call)}</code></div>)
      end)

    """
    <div class="suggestion">
      <div class="suggestion-header">→ Extract function</div>
      <code class="suggestion-sig">defp #{escape(s.name)}(#{escape(params)})</code>
      #{call_sites}
    </div>
    """
  end

  defp render_suggestion(%{kind: :extract_macro} = s) do
    params = if s.params == [], do: "", else: Enum.join(s.params, ", ")
    count = Map.get(s, :occurrence_count, 0)

    """
    <div class="suggestion">
      <div class="suggestion-header">→ Consider macro</div>
      <code class="suggestion-sig">defmacro #{escape(s.name)}(#{escape(params)})</code>
      <div class="call-site">#{count} occurrences across modules</div>
    </div>
    """
  end

  defp render_behaviour_suggestion(nil), do: ""

  defp render_behaviour_suggestion(%{
         callback_name: name,
         callback_arity: arity,
         modules: modules
       }) do
    args = List.duplicate("term()", arity) |> Enum.join(", ")
    mods = Enum.join(modules, ", ")

    """
    <div class="suggestion" style="border-left-color: #61afef;">
      <div class="suggestion-header">→ Consider behaviour</div>
      <code class="suggestion-sig">@callback #{escape(to_string(name))}(#{args})</code>
      <div class="call-site">Implemented identically in #{escape(mods)}</div>
    </div>
    """
  end

  defp type_badge(:type_i), do: "I"
  defp type_badge(:type_ii), do: "II"
  defp type_badge(:type_iii), do: "≈"

  defp badge_class(:type_i), do: "badge-i"
  defp badge_class(:type_ii), do: "badge-ii"
  defp badge_class(:type_iii), do: "badge-iii"

  defp format_similarity(nil), do: ""
  defp format_similarity(sim), do: "  #{Float.round(sim * 100, 1)}%"

  defp file_uri(path, line) do
    abs = Path.expand(path)
    if line > 0, do: "file://#{abs}#L#{line}", else: "file://#{abs}"
  end

  defp escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  if Code.ensure_loaded?(Makeup.Lexers.ElixirLexer) do
    alias Makeup.Styles.HTML.StyleMap

    defp highlight(code) do
      Makeup.highlight_inner_html(code, lexer: Makeup.Lexers.ElixirLexer)
    end

    defp makeup_css do
      light = Makeup.stylesheet(StyleMap.default_style(), "snippet")
      dark = Makeup.stylesheet(StyleMap.one_dark_style(), "snippet")

      """
      @media(prefers-color-scheme:light){#{light}}
      @media(prefers-color-scheme:dark){#{dark}}
      """
    end
  else
    defp highlight(code), do: escape(code)
    defp makeup_css, do: ""
  end

  defp css do
    """
    *{margin:0;padding:0;box-sizing:border-box}
    :root{
      --bg:#1a1a2e;--surface:#16213e;--border:#2a2a4a;
      --text:#e0e0e0;--text-dim:#888;--accent:#7c3aed;
      --red:#ef4444;--yellow:#eab308;--magenta:#d946ef;
      --green:#22c55e;--blue:#60a5fa;--cyan:#22d3ee;
    }
    @media(prefers-color-scheme:light){
      :root{
        --bg:#f8f9fa;--surface:#fff;--border:#e0e0e0;
        --text:#1a1a1a;--text-dim:#666;--accent:#7c3aed;
        --red:#dc2626;--yellow:#ca8a04;--magenta:#c026d3;
        --green:#16a34a;--blue:#2563eb;--cyan:#0891b2;
      }
    }
    body{font-family:system-ui,-apple-system,sans-serif;background:var(--bg);color:var(--text);max-width:900px;margin:0 auto;padding:2rem 1rem}
    header{margin-bottom:2rem}
    h1{font-size:1.5rem;color:var(--accent)}
    .subtitle{color:var(--text-dim);font-size:.9rem}
    .summary{display:flex;flex-wrap:wrap;gap:1rem;margin-bottom:2rem}
    .stat{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:1rem 1.25rem;min-width:120px;flex:1}
    .stat-value{display:block;font-size:1.5rem;font-weight:700}
    .stat-label{font-size:.75rem;color:var(--text-dim);text-transform:uppercase;letter-spacing:.05em}
    .no-clones{color:var(--green);font-size:1.1rem;padding:2rem 0}
    .clone-card{background:var(--surface);border:1px solid var(--border);border-radius:8px;margin-bottom:1rem;overflow:hidden}
    .clone-card summary{cursor:pointer;padding:1rem;display:flex;align-items:center;gap:.75rem;list-style:none}
    .clone-card summary::-webkit-details-marker{display:none}
    .clone-card summary::before{content:"▸";color:var(--text-dim);transition:transform .15s}
    .clone-card[open] summary::before{transform:rotate(90deg)}
    .badge{font-size:.7rem;font-weight:700;padding:2px 8px;border-radius:4px;font-family:monospace}
    .badge-i{background:var(--red);color:#fff}
    .badge-ii{background:var(--yellow);color:#000}
    .badge-iii{background:var(--magenta);color:#fff}
    .clone-title{font-weight:600}
    .meta{color:var(--text-dim);font-size:.85rem;margin-left:auto}
    .clone-body{padding:0 1rem 1rem}
    .locations{margin-bottom:.75rem}
    .location{display:block;color:var(--cyan);font-size:.85rem;font-family:monospace;text-decoration:none;padding:2px 0}
    .location:hover{text-decoration:underline}
    .snippet{margin-bottom:.75rem}
    .snippet-label{font-size:.7rem;color:var(--text-dim);text-transform:uppercase;margin-bottom:4px}
    pre{background:var(--bg);border:1px solid var(--border);border-radius:6px;padding:.75rem 1rem;overflow-x:auto;font-size:.8rem;line-height:1.5}
    code{font-family:'SF Mono',Monaco,Consolas,'Liberation Mono',monospace}
    #{makeup_css()}
    .snippet .unselectable{display:none}
    .suggestion{border-top:1px solid var(--border);margin-top:.75rem;padding-top:.75rem}
    .suggestion-header{color:var(--green);font-weight:600;margin-bottom:.25rem}
    .suggestion-sig{font-size:.85rem;display:block;margin-bottom:.5rem;color:var(--green)}
    .call-site{font-size:.8rem;color:var(--text-dim);padding:2px 0}
    .call-site code{color:var(--cyan)}
    footer{margin-top:3rem;text-align:center;color:var(--text-dim);font-size:.75rem}
    """
  end
end
