Import-Module ".\build-sql.psm1" -Force

[string] $image = "sql-samples"
[int]    $port = 1433

Clear-Host

Write-Host "`nbuilding sql server $image docker image, port: $port ...`n"

remove-existing-container $image

[string] $password = get-sa-password

add-sql-container $image $password $port

$dbs = read-json ".\dbs.json"

$dbs | ForEach-Object {

    $db = $_

    restore-db $image `
               $password `
               $db.title `
               $db.name `
               $db.backup `
               $db.sourceUrl
}

docker container stop $image *> $null

Write-Host "`nComplete!`n" -ForegroundColor Green