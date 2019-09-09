Import-Module ".\build-sql.psm1" -Force

$selected = select-database

[string] $container = $selected.container

if (!(remove-existing-container $container)) {
    exit
}

[int]    $port  = get-port-mapping $selected.portMapping
[string] $title = $selected.title

Write-Host "`nbuilding sql server $container docker container mapped to port: $port for $title...`n"

[string] $password = get-sa-password

add-sql-container $container $password $port

if ($null -eq $selected.dbs)
{
    restore-db $container `
               $password `
               $title `
               $selected.name `
               $selected.backup `
               $selected.sourceUrl
} else {

    $selected.dbs | ForEach-Object {

        [object] $db = $_

        restore-db $container `
                   $password `
                   $title `
                   $db.name `
                   $db.backup `
                   $db.sourceUrl
    }
}

docker container stop $container *> $null

Write-Host "`nComplete!`n" -ForegroundColor Green
