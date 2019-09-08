Import-Module ".\build-sql.psm1" -Force

$selected = select-database "Delete" $true

if ($selected -is [array]) {

    $selected | ForEach-Object {

        remove-existing-container $_.image
    }
} else {
    remove-existing-container $selected.image
}
