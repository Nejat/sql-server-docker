Import-Module ".\build-sql.psm1" -Force

[object] $selected  = select-database | Select-Object -Last 1
[object] $db        = $selected.db
[string] $container = $db.container

if (!(remove-existing-container $container)) {
    exit
}

[int]    $port  = get-port-mapping $db.portMapping
[string] $title = $db.title

Write-Host "`nbuilding sql server $container docker container mapped to port: $port for $title...`n"

[string] $password = get-sa-password

add-sql-container $container $password $port $selected.edition

if (
        ![string]::IsNullOrWhiteSpace($db.sourceUrl) `
   -and ![string]::IsNullOrWhiteSpace($db.backup) `
   ) {
    if ($null -eq $db.dbs) {
        restore-db $container `
                $password `
                $title `
                $db.name `
                $db.backup `
                $db.sourceUrl
    } else {

        $db.dbs | ForEach-Object {

            [object] $db = $_

            restore-db $container `
                    $password `
                    $title `
                    $db.name `
                    $db.backup `
                    $db.sourceUrl
        }
    }
} else {
    Write-Host "`nno database was restored" -ForegroundColor DarkMagenta
}

#docker container stop $container *> $null

Write-Host ""

docker container ls -a

Write-Host "`nComplete!`n" -ForegroundColor Green
