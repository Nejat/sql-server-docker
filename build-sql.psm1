function read-json {

    param (
        [string] $sourceFile
    )
    
    Get-Content $sourceFile | Out-String | ConvertFrom-Json
}

[object] $config = read-json ".\dbs.json"

function convert-value {

    param (
        [parameter(ValueFromPipeline)]
        [string] $source
    )

    if ($source -eq "null" -or $null -eq $source) {
        return $null
    } else {
        [int] $result = [int]::MinValue

        if ([int]::TryParse($source, [ref]$result)) {
            return $result
        }

        [long] $result = [long]::MinValue

        if ([long]::TryParse($source, [ref]$result)) {
            return $result
        }

        [double] $result = [double]::MinValue

        if ([double]::TryParse($source, [ref]$result)) {
            return $result
        }

        [bool] $result = $false

        if ([bool]::TryParse($source, [ref]$result)) {
            return $result
        }

        [datetime] $result = [datetime]::MinValue

        if ([datetime]::TryParse($source, [ref]$result)) {
            return $result
        }

        [guid] $result = [guid]::Empty

        if ([guid]::TryParse($source, [ref]$result)) {
            return $result
        }

        return $source
    } 
}

function add-properties {

    param (
          [PSObject]  $source
        , [hashtable] $newProperties
    )
    
    [hashtable] $combined = @{}

    $source.PSObject.properties | ForEach-Object {

        $combined[$_.Name] = $_.Value
    }

    $newProperties.Keys | ForEach-Object {
        $combined[$_] = $newProperties[$_]
    }

    New-Object -TypeName PSObject -Property $combined
}

function get-port-mapping {

    param (
        [int] $default = 1433
    )

    [int]  $port    = 0
    [bool] $invalid = $true

    Write-Host ""

    do {

        $value = Read-Host "enter a port to map 1433/tcp to host (enter to use $default)"

        if ($null -eq $value -or $value -eq "") {
            $port    = $default
            $invalid = $false
        } 
        else {
            try {
                $port = [int]$value
            }
            catch {
                $port = -1
            }
    
            $invalid = $port -lt 1024 -or $port -gt 65535

            if ($invalid) {
                Write-Host "`nyou must use a value tcp port between 1024 and 65535`n" -ForegroundColor Red
            }
        }
    } while ($invalid)

    $port
}

function select-database {

    param (
        [string] $verb          = "Build"
      , [bool]   $allOption     = $false
      , [bool]   $chooseEdition = $true
    )

    [object[]] $dbs = $config.dbDefinitions
    [object]   $choice

    do {
        Clear-Host
        Write-Host "======== SQL Server Docker ========`n"

        [int] $choices = 0

        $dbs | ForEach-Object {

            $choices++

            [string] $title = $_.title

            Write-Host "$choices $verb $title Image"
        }

        if ($allOption) {
            Write-Host "`nA: Press 'A' select all." -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }

        Write-Host "Q: Press 'Q' to quit.`n" -ForegroundColor DarkGray

        $command = Read-Host "Choose a command"

        Write-Host ""

        if ($command -eq "q") {
            exit
        }

        if ($allOption -and $command -eq 'a') {
            $choice = $dbs
            break
        }
    } while ($command -lt 1 -or $command -gt $choices)

    if ($null -eq $choice) {

        $choice = $dbs[$command - 1]

        if ($null -ne $choice.include) {

            [object[]] $includedDbs = $dbs | ForEach-Object {

                [object] $db = $_

                if ($null -ne $db.name -and $choice.include.Contains($db.name)) {
                    $db | Select-Object "name", "backup", "sourceUrl"
                }
            }

            $choice = add-properties $choice @{ dbs = $includedDbs }
        }
    }

    if ($chooseEdition -ne $true) {
        return $choice
    }

    [string[]] $editions = $config.editions
    [string]   $edition  = $null

    if (![string]::IsNullOrWhiteSpace($choice.edition)) {
        $config.defaultEdition = $choice.edition
    }

    do {
        Clear-Host
        Write-Host "===== Available Editions =====`n"

        [int] $choices = 0

        $editions | ForEach-Object {

            $choices++

            [string] $title = $_

            Write-Host "$choices $title Edition"
        }

        Write-Host ""
        Write-Host "Q: Press 'Q' to quit.`n" -ForegroundColor DarkGray

        $edition = Read-Host "Choose an Edition (default $($config.defaultEdition))"

        if ($edition -eq [string]::Empty) {
            break
        }

        Write-Host ""

        if ($edition -eq "q") {
            exit
        }
    } while ($edition -lt 1 -or $edition -gt $choices)

    if ($edition -eq [string]::Empty) {
        $edition = $config.defaultEdition
    } else {
        $edition = $editions[$edition]
    }

    [hashtable] $result = @{
        db      = $choice
        edition = $edition
    }

    New-Object -TypeName PSObject -Property $result
}

function get-backup {

    param (
          [string] $title
        , [string] $backupFile
        , [string] $dbImageUrl
    )

    if (!(Test-Path $backupFile -PathType Leaf)) {

        Write-Host "retreiving backup image for $title ...`n"
    
        Invoke-WebRequest -OutFile $backupFile $dbImageUrl
    }
}

function copy-backup {

    param (
          [string] $container
        , [string] $title
        , [string] $backupFile
    )
    
    Write-Host "copy $title backup $backupFile to " -NoNewline
    Write-Host "container" -NoNewline -ForegroundColor Magenta
    Write-Host " '" -NoNewline
    Write-Host "$container" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' ...`n"
    
    docker cp $backupFile ${container}:/var/opt/mssql/backup
}

function read-filelist {

    param (
          [string] $container
        , [string] $pswd
        , [string] $backupFile
    )

    [string[]] $list = docker exec -it $container /opt/mssql-tools/bin/sqlcmd -S localhost `
                        -U SA -P "$pswd" `
                        -Q "RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/backup/$backupFile'"
    
    [int[]] $lengths = $list[1].Split(' ') | ForEach-Object { $_.Length }
    [int]   $start   = 0 

    [string[]] $columnNames = 0..($lengths.Length - 1) | ForEach-Object {
        
        [int] $col = $_
        
        if ($col -ne 0) { 
            $start += $lengths[$col - 1] + 1
        }
         
        $list[0].Substring($start, $lengths[$col]).Trim()  
    }
    
    2..($list.Length - 3) | ForEach-Object {
    
        [string] $row   = $_
        [int]    $start = 0 
    
        [object[]] $values = 0..($lengths.Length - 1) | ForEach-Object {
         
            [int] $col = $_
    
            if ($col -ne 0) { 
                $start += $lengths[$col - 1] + 1
            }
    
            try {
                [string] $value = $list[$row].Substring($start, $lengths[$col]).Trim() 

                $value | convert-value
            }
            catch {
                [string] $columnName = $columnNames[$col]
                [int]    $size       = $list[$row].Length
                [int]    $len        = $lengths[$col]

                Write-Host "row: $row, size: $size, start: $start, len: $len"
                Write-Host "Failed on value '$value' column $col '$columnName': $_" -ForegroundColor Red
            }
        }
 
        [hashtable] $properties = @{ }
    
        0..($lengths.Length - 1) | ForEach-Object { 
    
            [string] $col = $_
    
            try {
                $properties.Add($columnNames[$col], $values[$col])
            }
            catch {
                Write-Host "Failed on column $col '${columnNames[$col]}': $_" -ForegroundColor Red
            }
        }
    
        New-Object -TypeName PSObject -Property $properties
    }
}

function convert-file-moves {

    param (
        [PSObject[]] $files
    )

    $moves = $files | ForEach-Object {

        $file = $_

        [string] $logical  = $file.LogicalName
        [string] $physical = $file.PhysicalName.Split('\') | Select-Object -Last 1
    
        "MOVE '$logical' TO '/var/opt/mssql/data/$physical'"
    }

    [string]::Join(", ", $moves)
}

function restore-backup {

    param (
          [string] $container
        , [string] $pswd
        , [string] $title
        , [string] $db
        , [string] $backupFile
        , [string] $moves
    )
    
    Write-Host "restoring $title ...`n"
    
    docker exec -it $container /opt/mssql-tools/bin/sqlcmd `
        -S localhost -U SA -P "$pswd" `
        -Q "RESTORE DATABASE $db FROM DISK = '/var/opt/mssql/backup/$backupFile' WITH $moves"
    
    Write-Host ""
    
    docker exec -it $container /opt/mssql-tools/bin/sqlcmd `
        -S localhost -U SA -P "$pswd" `
        -Q "SELECT Name FROM sys.Databases"
    
    Write-Host ""
}

function restore-db {

    param (
          [string] $container
        , [string] $pswd
        , [string] $title
        , [string] $db
        , [string] $backupFile
        , [string] $dbImageUrl
    )

    add-folder-to-container  $container "backup" "/var/opt/mssql/backup"

    get-backup $title $backupFile $dbImageUrl
    
    copy-backup $container $title $backupFile
    
    [PSObject[]] $files = read-filelist $container $pswd $backupFile
    [string]     $moves = convert-file-moves $files

    restore-backup $container $pswd $title $db $backupFile $moves

    Remove-Item $backupFile

    docker exec ${container} rm -rf /var/opt/mssql/backup/$backupFile
}

function get-sa-password {
    
    Write-Host "`nsa password must pass sql server secure password rules`n" -ForegroundColor DarkCyan

    do {
        [System.Security.SecureString] $password1 = Read-Host -AsSecureString "enter secure sa password"
        [string]                       $password1 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password1))
        [System.Security.SecureString] $password2 = Read-Host -AsSecureString "enter secure sa password again"
        [string]                       $password2 = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2))
    
        [bool] $noMatch = $password1 -cne $password2
        [bool] $blank   = $password1 -eq ""

        if ($noMatch) {
            Write-Host "`nentered passwords" -NoNewline
            Write-Host " do no match`n" -ForegroundColor Red
        } 
    
        if ($blank) {
            Write-Host "`nsa password" -NoNewline
            Write-Host " can not be blank`n" -ForegroundColor Red
        }
    } while ($noMatch -or $blank)
    
    Write-Host "`nsuccessfully" -NoNewline -ForegroundColor Green
    Write-Host " entered matching passowrds `n"

    $password1
}

function remove-existing-container {

    param (
        [string] $container
    )

    [string] $confirm = Read-Host "continuing will remove any existing container named '$container' ('y' to continue)"

    if ($confirm -ne "y") {
        Write-Host ""

        return $false
    }

    docker container stop $container *> $null
    docker container rm $container   *> $null
    docker volume rm $container-data *> $null

    return $true
}

function get-latest-image {

    Write-Host "pulling latest " -NoNewline
    Write-Host "sql server $($config.image)" -NoNewline -ForegroundColor DarkBlue
    Write-Host " image" -NoNewline -ForegroundColor Magenta
    Write-Host "  ...`n"
    
    [string] $image = $config.image

    docker pull mcr.microsoft.com/mssql/server:$image
}

function add-sql-container {

    param (
          [string] $container
        , [string] $pswd
        , [string] $sqlPort
        , [string] $edition = "Developer"
    )

    get-latest-image

    Write-Host "`ncreating " -NoNewline
    Write-Host "sql server $($config.image)" -NoNewline -ForegroundColor DarkBlue
    Write-Host " container" -NoNewline -ForegroundColor Magenta
    Write-Host " '" -NoNewline
    Write-Host "$container" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' and a " -NoNewline
    Write-Host "data volume container" -NoNewline -ForegroundColor Magenta
    Write-Host " '" -NoNewline
    Write-Host "$container-data" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' ... " -NoNewline

    [string] $image = $config.image

    [string] $id = docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$pswd" -e "MSSQL_PID=$edition" `
                        --name "$container" -p ${sqlPort}:1433 `
                        -v $container-data:/var/opt/mssql `
                        -d mcr.microsoft.com/mssql/server:$image

    Write-Host "created $id`n"
}

function add-folder-to-container {

    param (
          [string] $container
        , [string] $type
        , [string] $folder
    )

    Write-Host "create $type folder on '" -NoNewline
    Write-Host "$container" -NoNewline -ForegroundColor DarkYellow
    Write-Host "' ...`n"

    docker exec -it $container mkdir -p $folder
}

Export-ModuleMember -Function add-folder-to-container
Export-ModuleMember -Function add-sql-container
Export-ModuleMember -Function get-port-mapping
Export-ModuleMember -Function get-sa-password
Export-ModuleMember -Function read-json
Export-ModuleMember -Function remove-existing-container
Export-ModuleMember -Function restore-db
Export-ModuleMember -Function select-database