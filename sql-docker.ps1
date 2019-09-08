param
(
    [string]   $command   = 'stop',
    [string[]] $servers   = @('SQL-Dev','SQL-QA','SQL-Prod'),
    [int]      $port      = 1413,
    [int]      $increment = 10,
    [string]   $password  = 'P@s$$0rd!'
)

function new-servers
{
    param
    (
        [string[]] $servers,
        [int]      $port,
        [int]      $increment,
        [string]   $password
    )

    foreach ($server in $servers)
    {
        [string] $command = "docker run -e 'ACCEPT_EULA=Y' -e 'SA_PASSWORD=${pswd}' -e 'MSSQL_PID=Express' -p ${port}:1433 --name ${server} -d microsoft/mssql-server-linux:2017-latest"
        
        Invoke-Expression -Command $command
    
        $port = $port + 10
    }

    Invoke-Expression -Command 'docker ps -a'
}

function remove-servers
{
    param
    (
        [string[]] $servers,
        [int]      $port,
        [int]      $increment,
        [string]   $password
    )

    foreach ($server in $servers)
    {
        [string] $command = "docker stop ${server}"
        
        Invoke-Expression -Command $command

        $command = "docker rm ${server}"
        
        Invoke-Expression -Command $command
    
        $port = $port + 10
    }

    Invoke-Expression -Command 'docker ps -a'
}

function start-servers
{
    param
    (
        [string[]] $servers,
        [int]      $port,
        [int]      $increment,
        [string]   $password
    )

    foreach ($server in $servers)
    {
        [string] $command = "docker start ${server}"
        
        Invoke-Expression -Command $command
    
        $port = $port + 10
    }

    Invoke-Expression -Command 'docker ps -a'
}

function stop-servers
{
    param
    (
        [string[]] $servers,
        [int]      $port,
        [int]      $increment,
        [string]   $password
    )

    foreach ($server in $servers)
    {
        [string] $command = "docker stop ${server}"
        
        Invoke-Expression -Command $command
    
        $port = $port + 10
    }

    Invoke-Expression -Command 'docker ps -a'
}

switch ($command) {
    'create' 
    {
        new-servers $servers $port $increment $password
    }
    'delete' 
    {
        remove-servers $servers
    }
    'start' 
    {
        start-servers $servers
    }
    'stop' 
    {
        stop-servers $servers
    }
    Default 
    {
        Invoke-Expression -Command 'docker ps -a'
    }
}
