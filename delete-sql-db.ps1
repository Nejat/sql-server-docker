Import-Module ".\build-sql.psm1" -Force

if (!(test-docker)) {
    Write-Error "Docker is not running"
    exit
}

$selected = select-database "Delete" $true $false $false | Select-Object -Skip 0

if ($selected -is [array]) {

    $selected | ForEach-Object {
        $null = remove-existingContainer $_.container
    }
} else {
    $null = remove-existingContainer $selected.container
}

Write-Host ""

docker container ls -a

Write-Host ""