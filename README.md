# box-ps
Powershell sandboxing utility

## Installation
```
python -m pip install -e /<path to box-ps download>/pyboxps-<2.7|3.11>
export BOXPS=/<path to box-ps download>/
```

## Environment
```json
"BehaviorProps": {
    "code_import": ["code"],
    "code_create": ["code"],
    "binary_import": ["bytes"],
    "file_system": ["paths"],
    "script_exec": ["script"],
    "process": ["processes"],
    "new_object": ["object"],
    "network": ["uri"],
    "file_exec": ["files"],
    "memory": [],
    "environment_probe": []
}

"SubBehaviorProps": {
    "file_write": ["content"],
    "get_file_info": [],
    "change_directory": [],
    "file_read": [],
    "file_delete": [],
    "get_process_info": [],
    "kill_process": [],
    "pause_process": ["duration"],
    "import_dotnet_code": [],
    "start_process": [],
    "probe_os": [],
    "probe_language": [],
    "probe_date": [],
    "upload": ["content"],
    "write_to_memory": ["bytes"],
    "new_directory": [],
    "list_directory_contents": [],
    "check_for_file": [],
    "get_path": [],
    "import_dotnet_binary": [],
    "init_code_block": []
}
```

## Error return codes

```
argument error - 1
environment error - 2
bad input file - 3
sandboxing failure - 4
docker container operation error - 5
sandboxing timeout - 124
invalid script syntax - 6
```
