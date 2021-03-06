Import-Module ".\build-sql.psm1" -Force

if (!(test-docker)) {
    Write-Error "Docker is not running"
    exit
}

[object] $selected  = select-database | Select-Object -Last 1
[object] $db        = $selected.db
[string] $container = $db.container
[string] $image     = $selected.db.image

if (!(remove-existingContainer $container)) {
    exit
}

[int]    $port  = get-portMapping $db.portMapping
[string] $title = $db.title

Write-Host "`nbuilding sql server $container docker container mapped to port: $port for $title using $image ...`n"

[string] $password = get-saPassword
[string] $id = add-sqlContainer $container $image $password $port $selected.edition

if (
        ![string]::IsNullOrWhiteSpace($db.sourceUrl) `
   -and ![string]::IsNullOrWhiteSpace($db.backup) `
   -or  $null -ne $db.dbs `
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

wait-until $id "Controller finished waiting for completion of processing of the upgrade segment"

Write-Host "`nComplete, ready to use!`n" -ForegroundColor Green
