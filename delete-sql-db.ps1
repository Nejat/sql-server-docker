Import-Module ".\build-sql.psm1" -Force

$selected = select-database "Delete" $true $false | Select-Object -Skip 0

if ($selected -is [array]) {

    $selected | ForEach-Object {
        $null = remove-existing-container $_.container
    }
} else {
    $null = remove-existing-container $selected.container
}

Write-Host ""

docker container ls -a

Write-Host ""