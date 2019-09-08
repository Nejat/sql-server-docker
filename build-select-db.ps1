Import-Module ".\build-sql.psm1" -Force

$selected = select-database

[string] $image = $selected.image

remove-existing-container $image

[int]    $port  = get-port-mapping $selected.portMapping
[string] $title = $selected.title

Write-Host "`nbuilding sql server $image docker image mapped to port: $port for $title...`n"

[string] $password = get-sa-password

add-sql-container $image $password $port

if ($null -eq $selected.dbs)
{
    restore-db $image `
               $password `
               $title `
               $selected.name `
               $selected.backup `
               $selected.sourceUrl
} else {

    $selected.dbs | ForEach-Object {

        [object] $db = $_

        restore-db $image `
                   $password `
                   $title `
                   $db.name `
                   $db.backup `
                   $db.sourceUrl
    }
}

docker container stop $image *> $null

Write-Host "`nComplete!`n" -ForegroundColor Green
