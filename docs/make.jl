using Documenter
using SFTP

makedocs(
    modules=[SFTP],
    authors="Peter Bräuer <pb866.git@gmail.com> and contributors",
    sitename="Julia SFTP Documentation",
    format=Documenter.HTML(;
        canonical="https://LIM-AeroCloud.github.io/SFTP.jl",
        edit_link="dev",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ]
)

deploydocs(
    repo = "github.com/LIM-AeroCloud/SFTP.jl.git",
    devbranch="dev"
)
