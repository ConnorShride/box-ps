import subprocess
import os
import resource
import tempfile
import json
import shutil
import argparse
import sys

import errors
import boxps_report

####################################################################################################
class BoxPS:

    ################################################################################################
    def __init__(self, boxps_path=None, docker=False):

        # validate environment first
        self._boxps_path = self._validate_env(boxps_path, docker)
        
        self._install_dir = os.getenv("BOXPS")
        self._docker = docker
        
        with open(self._boxps_path + os.sep + "config.json", "r") as f:
            self._config = json.loads(f.read())

    ################################################################################################
    def _validate_env(self, boxps_path, docker):

        # BOXPS environment variable is set to the installation path of box-ps
        if boxps_path is None:

            boxps_path = os.getenv("BOXPS")

            if boxps_path is None:
                raise errors.BoxPSNoEnvVarError()
        
        if not os.path.isdir(boxps_path):
            raise errors.BoxPSBadEnvVarError()

        if not os.path.exists(boxps_path + os.sep + "box-ps.ps1"):
            raise errors.BoxPSBadInstallError("box-ps.ps1 not present in install directory: " + 
                boxps_path)

        if not os.path.exists(boxps_path + os.sep + "config.json"):
            raise errors.BoxPSBadInstallError("config.json not present in install directory: " +
                boxps_path)

        if docker and not os.path.exists(boxps_path + os.sep + "docker-box-ps.sh"):
            raise errors.BoxPSBadInstallError("docker-box-ps.sh not present in install directory:" +
                " " + boxps_path)

        # validate that the system has enough virtual memory per process allowed (4GB) or powershell
        # core can't run. Thanks Microsoft!
        mem_limit = resource.getrlimit(resource.RLIMIT_AS)[0]
        if mem_limit != -1:
            mem_limit_gb = mem_limit / (1024 ** 3)
            if mem_limit_gb < 4:
                raise errors.BoxPSVmemError()

        # we want to run docker. validate we can
        if docker:

            try:
                subprocess.check_call(["docker"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            except OSError as e:
                raise errors.BoxPSDependencyError("docker: " + str(e))
        
        # we want to run pwsh. validate we can
        else:

            try:
                subprocess.check_call(["pwsh", "-v"], stdout=subprocess.PIPE, 
                    stderr=subprocess.PIPE)
            except OSError as e:
                raise errors.BoxPSDependencyError("pwsh: " + str(e))
        
        return boxps_path

    ################################################################################################
    def sandbox(self,
                script=None,
                in_file=None,
                out_dir=None,
                env_vars=None,
                timeout=None,
                report_only=False):

        # if docker is true, you give script content, and set report only...

        # TODO use docker-box-ps.sh to never have the input script
        # touch disk, then implement report only so the artifacts don't touch disk either. SLICK.

        # must give either a script or an input file
        if script is None and in_file is None:
            raise ValueError("must give sandbox either the script contents or an input file path")

        # can't give both script contents and an input file path
        if script is not None and in_file is not None:
            raise ValueError("cannot give sandbox both the script contents and an input file path")

        # probably don't want to be giving out_dir and report_only
        if out_dir is not None and report_only:
            raise ValueError("can't give out_dir and report_only")

        # not yet supported by docker-box-ps.sh
        if env_vars and self._docker:
            raise ValueError("giving environment variables into a docker container isn't " +
                "supported yet")

        # create a temp output directory if not given one and we want one
        if out_dir is None and not report_only:
            out_dir = tempfile.mkdtemp(suffix="-boxps")

        if not self._docker:

            # write the script contents to a temp file
            if script is not None:
                in_file = tempfile.mkstemp(suffix="-boxps.ps1")[1]
                with open(in_file, "w") as f:
                    f.write(script)

            cmd = ["pwsh", "-noni", self._install_dir + os.sep + "box-ps.ps1", "-InFile", 
                in_file]

            # artifacts will still be written to disk in the working directory, but they're cleaned
            # up during box-ps execution
            if report_only:
                report_path = tempfile.mkstemp(suffix="-boxps.json")[1]
                cmd += ["-ReportOnly", report_path]
            else:
                cmd += ["-OutDir", out_dir]

            # write the env variables dict to a temp json file
            env_file = None
            if env_vars is not None:

                try:
                    env_file = tempfile.mkstemp(suffix="-boxps.env")[1]
                    with open(env_file, "w") as f:
                        f.write(json.dumps(env_vars))

                except Exception as e:
                    raise errors.BoxPSError("failed to write temp file for environment variables: " + 
                        str(e))

                cmd += ["-EnvFile", env_file]

            if timeout is not None:
                cmd = ["timeout", str(timeout)] + cmd

            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stdout, stderr = proc.communicate()

            # raise timeout error
            if timeout is not None and proc.returncode == 124:
                raise errors.BoxPSTimeoutError("box-ps failed to sandbox within " + str(timeout) + 
                    " second(s)")

        # sandbox within docker container. Use docker-box-ps.sh so we can pipe directly
        else:

            cmd = [self._install_dir + os.sep + "docker-box-ps.sh"]
            cmd += ["-p"] if script else [in_file]

            if report_only:
                report_path = tempfile.mkstemp(suffix="-boxps.json")[1]
                cmd += [report_path]
            else:
                cmd += ["-d", out_dir]

            if timeout:
                cmd += ["-t", str(timeout)]

            print(str(cmd))

            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

            if script:
                stdout, stderr = proc.communicate(script)
            else:
                stdout, stderr = proc.communicate()

            print("OUT...\n" + stdout)
            print("ERR...\n" + stderr)

            # until we can split out stderr and stdout from box-ps execution via docker exec
            out_lines = stderr.split()
            for line in out_lines:
                if line.startswith("[-]"):
                    raise errors.BoxPSSandboxError(line[line.index("[-] "):])

        # not stderr on the sandboxing sub-process. this means a critical error running the sandbox
        if stderr:
            raise errors.BoxPSSandboxError(stderr)

        report_path = out_dir + os.sep + "report.json" if not report_only else report_path

        # no report is also a critical error
        if not os.path.exists(report_path):

            msg = "no JSON report produced"

            # add sandbox stderr to error message if we got it
            sandbox_stderr = out_dir + os.sep + "stderr.txt"
            if os.path.exists(sandbox_stderr):
                with open(sandbox_stderr, "r") as f:
                    msg += "...\n" + f.read()

            raise errors.BoxPSSandboxError(msg)

        # deserialize the JSON report into a BoxPSReport
        #report = boxps_report.BoxPSReport(self._config, report_path=report_path)
        with open(report_path, "r") as f:
            report = json.loads(f.read())

        return report if report_only else (out_dir, report)

####################################################################################################
# CLI
####################################################################################################
if __name__ == "__main__":

    description = "Python CLI for box-ps."

    # note can only pipe powershell in without writing to file if using docker
    # note make sure that docker-box-ps.sh is executable if using docker container

    disclaimer = "DISCLAIMER: "
    disclaimer += "Designed for use on a linux machine. Using this on Windows systems has not been "
    disclaimer += "tested and is strongly advised against. Boxps will run powershell core on input "
    disclaimer += "scripts and attempt to intercept malicious behavior but this is by no means "
    disclaimer += "guaranteed. In any case box-ps and this module will place potentially "
    disclaimer += "malicious artifacts onto disk, even when used with the docker "
    disclaimer += "option. If not using the docker option, this will create a directory called "
    disclaimer += "'working' in the current working directory to place files necessary to run "
    disclaimer += "box-ps, which will be deleted after running "
    disclaimer += ". Giving powershell script content via stdin is supported but "
    disclaimer += "only for convenience. The script contents will still be written to disk in a "
    disclaimer += " temp directory."

    usages = "EXAMPLES\n\n"

    parser= argparse.ArgumentParser(description=description + disclaimer, epilog=usages, 
        formatter_class=argparse.RawDescriptionHelpFormatter)

    parser.add_argument("-i", "--install-path", required=False, action="store", help="path to " +
        "box-ps installation. Will otherwise look for env variable BOXPS")
    parser.add_argument("-d", "--docker", required=False, action="store_true", default=False, 
        help="run box-ps from within a docker container that has networking disconnected. " +
        "Conatiner is killed after each run.")
    parser.add_argument("-od", "--out-dir", required=False, action="store_true", default=False, 
        help="create an " +
        " output directory in which to place analysis results (artifacts, JSON report file, stdout, " + 
        "etc.) in the current working directory called either piped.boxed or <file>.boxed " +
        " depending on input option. Will use a temp directory by default.")
    parser.add_argument("-r", "--report-only", required=False, action="store_true", default=False,
        help="")
    parser.add_argument("-t", "--timeout", required=False, action="store", help="timeout for the " +
        "sandboxing in seconds")
    parser.add_argument("-e", "--env-file", required=False, action="store", help="path to JSON " +
        "formatted file mapping the names of environment variables that should be set in the " +
        "sandbox to their string values.")
    parser.add_argument("-p", "--piped", required=False, default=False, action="store_true", 
        help="whether or not to read the powershell script content in from STDIN. See disclaimer.")
    parser.add_argument("-pv", "--parameter-values", required=False, default=False, 
        action="store_true", help="whether or not to print all parameter values from actions")
    parser.add_argument("-sv", "--snip-values", required=False, default=True,
        action="store_true", help="whether or not to truncate printing absurdly long values " +
        "(longer than 10,000 characters)")
    parser.add_argument("-se", "--stderr", required=False, default=False, action="store_true", 
        help="print captured stderr from the script")
    parser.add_argument("-l", "--layers", required=False, default=False, action="store_true",
        help="whether or not to print all the 'layers' of the script including the initial script")
    parser.add_argument("-a", "--all", required=False, default=False, action="store_true",
        help="print everything we can unsnipped")
    parser.add_argument("-f", "--file", required=False, action="store", help="path to powershell " +
        "script file to sandbox.")

    # TODO updated description, usages, disclaimer


    boxps = BoxPS(boxps_path=None, docker=True)
    report = boxps.sandbox(script=sys.stdin.read(),
                        out_dir=None,
                        report_only=True)

    #print(out_dir)
    print(report["Actions"][0]["Actor"])
    exit(-1)

    args = parser.parse_args()

    # further arg validation
    
    # must give either a script or an input file
    if not args.piped and args.file is None:
        print("[-] must give either piped script contents or an input file path")
        exit(-1)

    # can't give both script contents and an input file path
    if args.piped and args.file is not None:
        print("[-] can't give both the piped script contents and an input file path")
        exit(-1)

    # can't have an output directory and a report only
    if args.out_dir and args.report_only:
        print("[-] can't have a report only and an output directory")
        exit(-1)

    if args.all:
        args.snip_values = False
        args.parameter_values = True
        args.layers = True
        args.stderr = True

    # decide where to put the output analysis directory
    out_dir = None
    if args.out_dir and args.piped:
        out_dir = "piped.boxed"
    elif args.out_dir:
        out_dir = os.path.basename(args.file) + ".boxed"

    # read in environment variable input file if given
    env_vars = None
    if args.env_file:
        with open(args.env_file, "r") as f:
            env_vars = json.loads(f.read())

    boxps = BoxPS(boxps_path=args.install_path, docker=args.docker)

    # sandbox powershell with piped input or input file path
    if args.piped:
        out_dir, report = boxps.sandbox(script=sys.stdin.read(), 
                                        out_dir=out_dir, 
                                        env_vars=env_vars, 
                                        timeout=args.timeout)
    else:
        out_dir, report = boxps.sandbox(in_file=args.file, 
                                        out_dir=out_dir, 
                                        env_vars=env_vars, 
                                        timeout=args.timeout)
    
    # pretty print a list of actions
    def print_actions(actions, parameters=False):

        for action in actions:
            print("-" * 100)

            print(action.actor + "\n")
            print("Action ID: " + str(action.id))

            print "Behaviors:",
            for b in action.behaviors:
                print b.name,
            print "\nSub-Behaviors:",
            for b in action.sub_behaviors:
                print b.name,
            print("\n")

            print("Behavior Properties...\n")
            for behavior_property in action.behavior_properties.keys():
                print(behavior_property.upper() + "\n")
                value_str = str(action.behavior_properties[behavior_property])
                if args.snip_values and len(value_str) > 10000:
                    print(value_str[:10000] + " ......\nSNIPPED")
                else:
                    print(value_str)

            # print the values of the parameters like behavior properties
            if args.parameter_values:
                print("\nParameters...\n")
                for parameter in action.parameters.keys():
                    print(parameter.upper() + "\n")
                    value_str = str(action.parameters[parameter])
                    if args.snip_values and len(value_str) > 10000:
                        print(value_str[:10000] + " ......\nSNIPPED")
                    else:
                        print(value_str)
                    print("")

            # just print the parameters used
            else:
                print "\nParameters :",
                for p in action.parameters.keys():
                    print p,
                print("")

            if action.extra_info:
                print("\nEXTRA INFO...\n\n" + action.extra_info)

            print("-" * 100)

    # pretty print a list of artifacts joined with some stuff about the action it came from
    def print_artifacts(artifacts):

        for artifact in artifacts:
            print("=" * 100)
            action = report.get_action(artifact.action_id)
            print("Action ID: " + str(artifact.action_id))
            print("Action Actor: " + str(action.actor))
            print "Action Behaviors:",
            for b in action.behaviors:
                print b.name,
            print "\nAction SubBehaviors:",
            for b in action.sub_behaviors:
                print b.name,
            print("\nSHA256: " + artifact.sha256)
            print("File Type: " + artifact.file_type)
            print("=" * 100)


    print("[+] ANALYSIS DIRECTORY: " + out_dir + "\n")

    print("[+] SCRIPT STDOUT...\n")
    with open(out_dir + os.sep + "stdout.txt") as f:
        print(f.read())

    if args.stderr:
        print("[+] SCRIPT STDERR...\n")
        with open(out_dir + os.sep + "stderr.txt") as f:
            print(f.read())

    if args.layers:
        print("[+] LAYERS...\n")
        with open(out_dir + os.sep + "layers.ps1") as f:
            print(f.read())

    if report.actions:
        print("[+] ACTIONS...\n")
        print_actions(report.actions, args.parameter_values)
        print("")
    else:
        print("[-] NO ACTIONS")

    if report.confident_net_iocs:
        print("[+] CONFIDENT NETWORK IOCs...\n") 
        for ioc in report.confident_net_iocs:
            print(ioc)
        print("")
    else:
        print("[-] NO CONFIDENT NETWORK IOCS\n")

    if report.artifacts:
        print("[+] ARTIFACTS...\n")
        print_artifacts(report.artifacts)
    else:
        print("[-] NO ARTIFACTS\n")
