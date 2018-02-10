using Documenter
using HartreeFockBogoliubov

makedocs()

deploydocs(
  deps = Deps.pip("pygments", "mkdocs", "python-markdown-math", # "mkdocs-material"
  ),
  repo = "github.com/kyungminlee/HartreeFockBogoliubov.jl.git",
  julia = "0.6",
  osname = "linux",
)
