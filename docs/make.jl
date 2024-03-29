using Documenter

using Pkg
docs_dir = joinpath(@__DIR__, "..")
project_dir = isempty(ARGS) ? @__DIR__() : joinpath(pwd(), ARGS[1])
Pkg.activate(project_dir)

using TestingUtilities

DocMeta.setdocmeta!(TestingUtilities, :DocTestSetup, :(using TestingUtilities); recursive=true)

makedocs(;
    modules=[TestingUtilities],
    authors="Curt Da Silva",
    repo="https://github.com/curtd/TestingUtilities.jl/blob/{commit}{path}#{line}",
    sitename="TestingUtilities.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://curtd.github.io/TestingUtilities.jl",
        edit_link="main",
        assets=String[],
        ansicolor=true
    ),
    pages=[
        "Home" => "index.md",
        "Settings" => "settings.md",
        "API" => "api.md"
    ],
    warnonly=[:missing_docs]
)

deploydocs(;
    repo="github.com/curtd/TestingUtilities.jl.git",
    devbranch="main", push_preview=true
)
