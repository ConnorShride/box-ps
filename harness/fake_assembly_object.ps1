# Make a fake object for [System.Reflection.Assembly]::Load() stubs
# out some methods.
class StubbedAssembly : System.Reflection.Assembly {
    StubbedAssembly() {}
    [StubbedType] GetType([string] $typeName) {
        $behaviors = @("process")
        $subBehaviors = @()
        $behaviorProps = @{}
        $behaviorProps["type"] = $typeName
        RecordAction $([Action]::new($behaviors, $subBehaviors, "System.Reflection.Assembly\GetType", $behaviorProps, $MyInvocation, ""))
        return ([StubbedType]::new())
    }    
}

# Stubbed Type class for return by GetType().
class StubbedType {
    StubbedType() {}
    [StubbedMethod] GetMethod([string] $methodName, [object[]] $bindingArgs) {
        $behaviors = @("process")
        $subBehaviors = @()
        $behaviorProps = @{}
        $behaviorProps["method"] = $methodName
        RecordAction $([Action]::new($behaviors, $subBehaviors, "Type\GetMethod", $behaviorProps, $MyInvocation, ""))
        return ([StubbedMethod]::new())
    }    
}

# Stubbed Method class for return by Type::GetMethod().
class StubbedMethod {
    StubbedMethod() {}
    [string] Invoke([object[]] $something, [object[]] $methodArgs) {
        foreach ($methodArg in $methodArgs) {

            # Is this argument a byte array?
            if (-not ($methodArg -is [byte[]])) {
                continue
            }

            # Is this argument a possible PE byte array?
            if (($methodArg.Length -lt 10) -or ($methodArg[0] -ne 77) -or ($methodArg[1] -ne 90)) {
                continue
            }

            # Might have a PE byte array. Save it as a potential artifact.
            $behaviors = @("binary_import")
            $subBehaviors = @()
            $behaviorProps = @{}
            $behaviorProps["bytes"] = $methodArg
            RecordAction $([Action]::new($behaviors, $subBehaviors, "MethodInfo\Invoke", $behaviorProps, $MyInvocation, ""))
        }
        return "??"
    }    
}

([StubbedAssembly]::new())
