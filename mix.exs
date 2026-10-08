defmodule BeamAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :beam_agent,
      version: "0.1.1",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      source_url: "https://github.com/vickris/beam-agent",
      homepage_url: "https://github.com/vickris/beam-agent",
      docs: [
        main: "readme",
        extras: ["README.md", "docs/telemetry.md"]
      ]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {BeamAgent.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    A general-purpose, OTP-based agent harness for Elixir: an LLM tool-use
    loop with an injectable tool registry, configurable guardrails,
    pluggable post-run verification, deterministic context compression,
    a full execution trace, and supervised, concurrent agent runs.
    """
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "docs",
        "LICENSE",
        "CHANGELOG.md"
      ],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/vickris/beam-agent"
      }
    ]
  end

  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test"
      ]
    ]
  end
end
