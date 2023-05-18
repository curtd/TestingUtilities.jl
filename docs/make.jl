using Documenter

using Pkg
docs_dir = joinpath(@__DIR__, "..")
project_dir = isempty(ARGS) ? @__DIR__() : joinpath(pwd(), ARGS[1])
Pkg.activate(project_dir)

using TestingUtilities

DocMeta.setdocmeta!(TestingUtilities, :DocTestSetup, :(using TestingUtilities); recursive=true)

makedocs(;
    modules=[TestingUtilities],
    authors="Curt Da Silva <curt.dasilva@gmail.com>",
    repo="https://github.com/curtd/TestingUtilities.jl/blob/{commit}{path}#{line}",
    sitename="TestingUtilities.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://curtd.github.io/TestingUtilities.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "API" => "api.md"
    ],
)

deploydocs(;
    repo="github.com/curtd/TestingUtilities.jl",
    devbranch="main",
    julia = "1.6"
)
