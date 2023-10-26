#!/usr/bin/env python3

import argparse
import json
import os
import resource
import shutil
import subprocess
import sys
import tempfile

import pyboxps.boxps_report as boxps_report
import pyboxps.errors as errors


####################################################################################################
def safe_str_convert(s):
    """
    Convert something to an ASCII str without throwing a unicode decode error.

    @param s (any) The thing to convert to a string.

    @return (str) The thing as an ASCII str.
    """

    # Sanity check.
    if s is None:
        return s

    # Handle bytes-like objects (python3).
    was_bytes = isinstance(s, bytes)
    try:
        if isinstance(s, bytes):
            s = s.decode("latin-1")
    except (UnicodeDecodeError, UnicodeEncodeError, SystemError):
        # python3
        if isinstance(s, bytes):
            from core.curses_ascii import isprint

            r = ""
            for c in s:
                curr_char = chr(c)
                if isprint(curr_char):
                    r += curr_char
            return r

    # Do the actual string conversion.
    r = None
    try:
        r = str(s)
    except UnicodeEncodeError:
        import string

        try:
            r = s.encode("latin-1")
        except UnicodeDecodeError:
            r = "".join(filter(lambda x: x in string.printable, s))
        except UnicodeEncodeError:
            r = "".join(filter(lambda x: x in string.printable, s))
        except SystemError:
            r = "".join(filter(lambda x: x in string.printable, s))
    return r


####################################################################################################
class BoxPS:
    ################################################################################################
    def __init__(self, boxps_path=None, docker=False):
        """
        Creates a BoxPS sandboxing object. Validates the environment is set up correctly, so this
        will raise some kind of BoxPSEnvError if something's not right.

        @param boxps_path (str) optional path to box-ps installation
        @param docker (bool) whether or not to use docker to sandbox
        """

        # validate environment first
        self._boxps_path = self._validate_env(boxps_path, docker)

        self._install_dir = os.getenv("BOXPS")
        self._docker = docker

        # TODO write a class for ingesting the config in python and within box-ps
        with open(self._boxps_path + os.sep + "config.json", "r") as f:
            self._config = json.loads(f.read())

    ################################################################################################
    def _validate_env(self, boxps_path, docker):
        """
        Validate that there is a valid box-ps installation and a valid and accessible docker
        installation if the user wants to use it. If boxps_path is None, will look for an
        environment variable named "BOXPS" to conatin the path. Will also validate that the system
        has at least 4GB of memory available to the process, and we can open a pwsh subprocess if
        not using docker. Checks are done in the following order and exceptions are raised if any
        fail, short-cicuiting the rest of the checks.

        1. is BOXPS env variable present (if boxps_path is None)
        2. is the box-ps install path a directory
        3. is box-ps.ps1 and config.json present in the install dir
        4. is docker-box-ps.sh present in the install dir and executable (if using docker)
        5. is there at least 4GB of memory available
        5. can this process run the docker command (if using docker)
        6. can this process run the pwsh command (if not using docker)

        @param boxps_path (str) optional path to box-ps installation to validate
        @param docker (bool) whether or not to validate a docker installation

        @return (str) path to the box-ps installation
        """

        # BOXPS environment variable is set to the installation path of box-ps
        if boxps_path is None:
            boxps_path = os.getenv("BOXPS")

            if boxps_path is None:
                raise errors.BoxPSNoEnvVarError()

        if not os.path.isdir(boxps_path):
            raise errors.BoxPSBadEnvVarError()

        if not os.path.exists(boxps_path + os.sep + "box-ps.ps1"):
            raise errors.BoxPSBadInstallError("box-ps.ps1 not present in install directory: " + boxps_path)

        if not os.path.exists(boxps_path + os.sep + "config.json"):
            raise errors.BoxPSBadInstallError("config.json not present in install directory: " + boxps_path)

        if docker and not os.path.exists(boxps_path + os.sep + "docker-box-ps.sh"):
            raise errors.BoxPSBadInstallError("docker-box-ps.sh not present in install directory:" + " " + boxps_path)

        if docker:
            try:
                subprocess.check_call(boxps_path + os.sep + "docker-box-ps.sh", stderr=subprocess.PIPE)
            except OSError as e:
                raise errors.BoxPSBadInstallError("cannot execute docker-box-ps.sh: " + str(e))

        # validate that the system has enough memory (4GB) or powershell core can't run
        # Thanks Microsoft!
        memory_gb = int((os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")) / (1024**3))
        if memory_gb < 4:
            raise errors.BoxPSMemError()

        # we want to run docker. validate we can
        if docker:
            try:
                subprocess.check_call(["docker"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            except OSError as e:
                raise errors.BoxPSDependencyError("docker: " + str(e))

        # we want to run pwsh. validate we can
        else:
            limit = self._unset_soft_vmem_limit()

            try:
                subprocess.check_call(["pwsh", "-v"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            except OSError as e:
                raise errors.BoxPSDependencyError("pwsh: " + str(e))

            self._reset_soft_vmem_limit(limit)

        return boxps_path

    ################################################################################################
    def _unset_soft_vmem_limit(self):
        """
        Queries for any soft limits on memory for the process. If there are some set, unsets them.

        @return (int) limit on soft memory, or None if there isn't one
        """

        mem_limit = resource.getrlimit(resource.RLIMIT_AS)[0]
        if mem_limit != -1:
            resource.setrlimit(resource.RLIMIT_AS, (-1, -1))
            return mem_limit
        return None

    ################################################################################################
    def _reset_soft_vmem_limit(self, mem_limit):
        """
        Resets the soft limit on the processes memory if there was one.
        """

        if mem_limit is not None:
            resource.setrlimit(resource.RLIMIT_AS, (mem_limit, -1))

    ################################################################################################
    def sandbox(
        self, script=None, in_file=None, out_dir=None, env_vars=None, timeout=None, report_only=False, report_file=None
    ):
        """
        Sandbox powershell to produce a BoxPSReport and other script artifacts if desired. Unlimits
        any soft memory limits on processes during the sanboxing, then resets them.

        INPUT...
        Must take either raw script content or a path to an input script, but not both. Environment
        variables that the script expects to be set may be given in a dict to env_vars. A timeout
        for the sandboxing may be given in seconds. A BoxPSTimeoutError is raised on timeout.

        DOCKER..
        Will use the docker-box-ps.sh bash script to containerize the sandbox if the BoxPS object
        was initialized with the docker flag set. docker-box-ps.sh will always pull the latest
        box-ps docker container to do the sandboxing. If giving raw script content, this method will
        pipe the script into a file within the docker container through docker-box-ps.sh, so the
        script is never written to disk outside the container.

        OUTPUT FILES/DIRECTORIES...
        This method will always produce a full analysis output directory on disk unless using docker
        AND the report_only flag is given. The location of the analysis directory can be customized
        with the out_dir argument, but this cannot be done while giving the report_only flag, and if
        out_dir is not given the analysis directory will be placed in a temp directory named
        <random>-boxps.

        This method will also always produce a "working" directory in the current working directory
        that contains all the files the full analysis directory would contain, regardless of your
        out_dir and report_only preferences, unless you're using docker in which case that directory
        will be written in the container only.

        The JSON report will always be written to disk somewhere named either report.json in the
        full analysis directory, in a temp folder named <random>-boxps.json, or at the path given in
        report_file.

        ValueErrors will be raised if arguments are given in an incompatible combination.

        @param script (str) raw script content
        @param in_file (str) path to input script
        @param out_dir (str) output path to full analysis directory
        @param env_vars (dict) map of environment variable names to string values for the script
        environment
        @param timeout (int) timeout for script sandboxing in seconds
        @param report_only (bool) whether or not to return the path to a full analysis directory
        @param report_file (str) path to place the outputted JSON report

        @return (BoxPSReport) report_only is given, otherwise a tuple where the first element is the
        report and the second is the path to the full analysis directory
        """

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
            raise ValueError("giving environment variables into a docker container isn't " + "supported yet")

        # create a temp output directory if not given one and we want one
        if out_dir is None and not report_only:
            out_dir = tempfile.mkdtemp(suffix="-boxps")

        # decide where the output JSON report will live
        # or just one of them in the case of both out_dir and report_file
        if not report_only:
            report_path = out_dir + os.sep + "report.json"
        elif report_file:
            report_path = report_file
        else:
            report_path = tempfile.mkstemp(suffix="-boxps.json")[1]

        if not self._docker:
            # write the script contents to a temp file
            if script is not None:
                in_file = tempfile.mkstemp(suffix="-boxps.ps1")[1]
                with open(in_file, "w") as f:
                    f.write(script)

            cmd = ["pwsh", "-noni", self._install_dir + os.sep + "box-ps.ps1", "-InFile", in_file]

            if report_only:
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
                    raise errors.BoxPSError("failed to write temp file for environment variables: " + str(e))

                cmd += ["-EnvFile", env_file]

            if timeout is not None:
                cmd += ["-Timeout", str(timeout)]

            limit = self._unset_soft_vmem_limit()

            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            stdout, stderr = proc.communicate()

            self._reset_soft_vmem_limit(limit)

        # sandbox within docker container. Use docker-box-ps.sh so we can pipe directly into it
        else:
            cmd = [self._install_dir + os.sep + "docker-box-ps.sh"]
            cmd += ["-p"] if script else [in_file]

            # no artifacts written to disk outside the JSON report and in the docker container
            if report_only:
                cmd += [report_path]

            # user wants an output directory with artifacts
            else:
                cmd += ["-d", out_dir]

            if timeout:
                cmd += ["-t", str(timeout)]

            # in-memory script content. no input script file is written outside the docker container
            if script:
                proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                stdout, stderr = proc.communicate(input=script)
            else:
                proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                stdout, stderr = proc.communicate()

        # raise timeout error
        if timeout is not None and proc.returncode == 124:
            raise errors.BoxPSTimeoutError("failed to sandbox within " + str(timeout) + " second(s)")

        # not stderr on the sandboxing sub-process. this means a critical error running the sandbox
        if stderr:
            error = safe_str_convert(stderr).replace("[-] ", "")

            # raise invalid syntax error
            if proc.returncode == 6:
                raise errors.BoxPSScriptSyntaxError(error)

            raise errors.BoxPSSandboxError(error)

        # no report is also a critical error
        if not os.path.exists(report_path):
            msg = "no JSON report produced"

            # add sandbox stderr to error message if we got it
            sandbox_stderr = out_dir + os.sep + "stderr.txt"
            if os.path.exists(sandbox_stderr):
                with open(sandbox_stderr, "r") as f:
                    msg += "...\n" + f.read()

            raise errors.BoxPSSandboxError(msg)

        # logic is just cleaner this way since docker-box-ps.sh doesn't support putting report and
        # analysis dir in two different spots
        if not report_only and report_file:
            shutil.copyfile(report_path, report_file)

        # deserialize the JSON report into a BoxPSReport
        report = boxps_report.BoxPSReport(self._config, report_path=report_path)

        return report if report_only else (out_dir, report)


####################################################################################################
# CLI
####################################################################################################
def main_cli():
    description = """

Python CLI for box-ps.

DISCLAIMER

Designed for use on a linux machine. Using this on Windows systems has not been tested and is
strongly advised against. Box-ps will run powershell core on input scripts and attempt to intercept
malicious behavior but this is by no means guaranteed. In any case box-ps and this module will place
potentially malicious artifacts of some kind onto disk, be they embedded PEs or JSON formatted
malicious strings of code, regardless of the options used. This module will remove any soft limits
on memory during the sandboxing operation but reinstate them directly afterwards. Limits on virtual
memory don't seem to work well with PowerShell core on certain systems.

DOCKER

This module is capable of using docker to sandbox malicious scripts to strip the networking
capabilities of the script and constrain it's access to your file system. Options can be given to
prevent malicious artifacts (extracted embedded files) from being written to disk outside the
container. You can also pipe in the malicious script content to docker thereby preventing the script
from being written to disk as docker well. At a minimum, a JSON report of the scripts execution will
always be written to disk outside the container somewhere, either in a temp directory or the
directory you specify. !!NOTE!! The latest box-ps container is pulled from DockerHub if necessary on
each run, and I don't have structured releases yet, so you should update this module often to keep
it in sync with the box-ps installation in the latest container.

OUTPUT

If you haven't given the report_only option, the path to a full analysis directory will be printed
where you can retrieve any artifacts that may have been produced from analysis. The location of the
output directory can be dictated by --boxed-dir or --out-dir. Otherwise if report_only is not given
it will be placed in a temp directory named <random>-boxps. You can customize the path to the JSON
report with --report-file, which will duplicate the report if it's already in the analysis
directory. If not using the docker option, this will temporarily create a 'working' directory in the
current working directory necessary to run box-ps which contains all the stuff in the full analysis
directories, but will be deleted after running. If you pipe in script content to sandbox and are not
using docker, the script will be written to disk in a temp directory named <random>-boxps.ps1.

"""

    usages = """


EXAMPLES

To sandbox a script on disk outside a container, produce an analysis directory in temp...

python ./boxps.py --file ./example-script.ps1


to produce only a JSON report in temp (but still temporarily write artifacts to disk in the
working directory)...

python ./boxps.py --file ./example-script.ps1 --report-only


to produce an analysis directory called "example-script.ps1.boxed" in the current working directory
and another JSON report somewhere else...

python ./boxps.py --file ./example-script.ps1 --boxed-dir --report-file ./report.json


to pipe in script content, produce an analysis directory and the script content written to temp...

cat ./example-script.ps1 | python ./boxps.py --piped


to pipe in script content to a docker container and only produce a JSON report in temp...

cat ./example-script.ps1 | python ./boxps.py --piped --docker --report-only


to pipe in script content to a docker container and produce an analysis directory called
"script.boxed"...

cat ./example-script.ps1 | python ./boxps.py --piped --docker --boxed-dir


to show the most possible information from analysis...

cat ./example-script.ps1 | python ./boxps.py --piped --all


to show layers and parameter values from actions but snip the values, and produce an analysis
directory called "analysis"...

python ./boxps.py --file ./example-script.ps1 --layers --parameter-values --out-dir ./analysis

"""

    parser = argparse.ArgumentParser(
        description=description, epilog=usages, formatter_class=argparse.RawDescriptionHelpFormatter
    )

    parser.add_argument(
        "-i",
        "--install-path",
        required=False,
        action="store",
        help="path to " + "box-ps installation. Will otherwise look for env variable BOXPS.",
    )
    parser.add_argument(
        "-d",
        "--docker",
        required=False,
        action="store_true",
        default=False,
        help="run box-ps from within a docker container that has networking disconnected. "
        + "Conatiner is killed after each run.",
    )
    parser.add_argument(
        "-o",
        "--out-dir",
        required=False,
        action="store",
        help="create a full analysis results output directory (artifacts, JSON report file, "
        + "stdout, etc.) at the given path.",
    )
    parser.add_argument(
        "-bd",
        "--boxed-dir",
        required=False,
        default=False,
        action="store_true",
        help="create a full analysis results output directory in the current working directory "
        + "called <script_file_name>.boxed if using file input, or script.boxed if piping script "
        + "content as input.",
    )
    parser.add_argument(
        "-r",
        "--report-only",
        required=False,
        action="store_true",
        default=False,
        help="don't produce a full analysis results output directory. Using this option will "
        + "still result in all the same stuff being written in the 'working' directory which is "
        + "deleted after running, unless using docker.",
    )
    parser.add_argument(
        "-rf",
        "--report-file",
        required=False,
        action="store",
        help="path to the"
        + "output JSON report file. It is stored either in the full analysis results directory or "
        + "in temp by default.",
    )
    parser.add_argument(
        "-t", "--timeout", required=False, action="store", help="timeout for the " + "sandboxing in seconds."
    )
    parser.add_argument(
        "-e",
        "--env-file",
        required=False,
        action="store",
        help="path to JSON "
        + "formatted file mapping the names of environment variables that should be set in the "
        + "sandbox to their string values.",
    )
    parser.add_argument(
        "-p",
        "--piped",
        required=False,
        default=False,
        action="store_true",
        help="read the powershell script content in from STDIN. The script is still written to "
        + "disk in temp unless using docker.",
    )
    parser.add_argument(
        "-pv",
        "--parameter-values",
        required=False,
        default=False,
        action="store_true",
        help="print all parameter values from actions, not just behavior " + "property values.",
    )
    parser.add_argument(
        "-ns",
        "--no-snip",
        required=False,
        default=False,
        action="store_true",
        help="don't truncate absurdly long parameter and behavior property "
        + "values (longer than 10,000 characters).",
    )
    parser.add_argument(
        "-se",
        "--stderr",
        required=False,
        default=False,
        action="store_true",
        help="print captured stderr from the script. Only available if producing a full analysis "
        + "output directory.",
    )
    parser.add_argument(
        "-l",
        "--layers",
        required=False,
        default=False,
        action="store_true",
        help="print all the 'layers' of the script in the order they're deobfuscated.",
    )
    parser.add_argument(
        "-a", "--all", required=False, default=False, action="store_true", help="print everything we can unsnipped."
    )
    parser.add_argument(
        "-f", "--file", required=False, action="store", help="path to powershell " + "script file to sandbox."
    )
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

    # can't say you want a .boxed dir and give your own dir
    if args.boxed_dir and args.out_dir:
        print("[-] can't give both the boxed dir and out dir options")
        exit(-1)

    # requested the most verbose output
    if args.all:
        args.no_snip = True
        args.parameter_values = True
        args.layers = True
        args.stderr = True

    # warning for not yet supported
    if args.stderr and args.report_only:
        print("[-] printing standard error is not available with the report only option")

    # give the analysis directory a default .boxed dir
    if args.boxed_dir:
        args.out_dir = "script.boxed" if args.piped else os.path.basename(args.file) + ".boxed"

    # read in environment variable input file if given
    env_vars = None
    if args.env_file:
        with open(args.env_file, "r") as f:
            env_vars = json.loads(f.read())

    boxps = BoxPS(boxps_path=args.install_path, docker=args.docker)

    # powershell script is piped in
    script = None
    if args.piped:
        script = sys.stdin.read()

    print("[+] sandboxing...\n")

    if args.report_only:
        report = boxps.sandbox(
            script=script,
            in_file=args.file,
            out_dir=None,
            env_vars=env_vars,
            timeout=args.timeout,
            report_only=True,
            report_file=args.report_file,
        )
    else:
        out_dir, report = boxps.sandbox(
            script=script,
            in_file=args.file,
            out_dir=args.out_dir,
            env_vars=env_vars,
            timeout=args.timeout,
            report_only=False,
            report_file=args.report_file,
        )

    # pretty print a list of actions
    def print_actions(actions, parameters=False):
        for action in actions:
            print("-" * 100)

            print(action.actor + "\n")
            print("Action ID: " + str(action.id))

            print(
                "Behaviors:",
            )
            for b in action.behaviors:
                print(
                    b.name,
                )
            print(
                "\nSub-Behaviors:",
            )
            for b in action.sub_behaviors:
                print(
                    b.name,
                )
            print("\n")

            print("Behavior Properties...\n")
            for behavior_property in action.behavior_properties.keys():
                print(behavior_property.upper() + "\n")
                value_str = str(action.behavior_properties[behavior_property])
                if not args.no_snip and len(value_str) > 10000:
                    print(value_str[:10000] + " ......\nSNIPPED\n")
                else:
                    print(value_str + "\n")

            # print the values of the parameters like behavior properties
            if args.parameter_values:
                print("\nParameters...\n")
                for parameter in action.parameters.keys():
                    print(parameter.upper() + "\n")
                    value_str = str(action.parameters[parameter])
                    if not args.no_snip and len(value_str) > 10000:
                        print(value_str[:10000] + " ......\nSNIPPED\n")
                    else:
                        print(value_str + "\n")

            # just print the parameters used
            else:
                print(
                    "\nParameters Used:",
                )
                for p in action.parameters.keys():
                    print(
                        p,
                    )
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
            print(
                "Action Behaviors:",
            )
            for b in action.behaviors:
                print(
                    b.name,
                )
            print(
                "\nAction SubBehaviors:",
            )
            for b in action.sub_behaviors:
                print(
                    b.name,
                )
            print("\nSHA256: " + artifact.sha256)
            print("File Type: " + artifact.file_type)
            print("=" * 100)

    # pretty print the list of layers
    def print_layers(layers):
        for layer in layers:
            print("*" * 100)
            print(layer)
            print("*" * 100)

    # stderr, stdout, analysis directory only available with a full output directory
    # TODO put stdout in the analysis report
    if not args.report_only:
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
        layers = report.layers
        if layers:
            print_layers(layers)
            print("")
        else:
            print("[-] NO LAYERS\n")

    if report.actions:
        print("[+] ACTIONS...\n")
        print_actions(report.actions, args.parameter_values)
        print("")
    else:
        print("[-] NO ACTIONS\n")

    if report.confident_net_iocs:
        print("[+] CONFIDENT NETWORK IOCs...\n")
        for ioc in report.confident_net_iocs:
            print(ioc)
        print("")
    else:
        print("[-] NO CONFIDENT NETWORK IOCS\n")

    if report.aggressive_net_iocs:
        print("[+] AGGRESSIVE NETWORK IOCs...\n")
        for ioc in report.aggressive_net_iocs:
            print(ioc)
        print("")
    else:
        print("[-] NO AGGRESSIVE NETWORK IOCS\n")

    if report.confident_fs_iocs:
        print("[+] CONFIDENT FILE SYSTEM IOCs...\n")
        for ioc in report.aggressive_fs_iocs:
            print(ioc)
        print("")
    else:
        print("[-] NO CONFIDENT FILE SYSTEM IOCS\n")

    if report.aggressive_fs_iocs:
        print("[+] AGGRESSIVE FILE SYSTEM IOCs...\n")
        for ioc in report.aggressive_fs_iocs:
            print(ioc)
        print("")
    else:
        print("[-] NO AGGRESSIVE FILE SYSTEM IOCS\n")

    if report.artifacts:
        print("[+] ARTIFACTS...\n")
        print_artifacts(report.artifacts)
    else:
        print("[-] NO ARTIFACTS\n")

    if report.aggressive_artifacts:
        print("[+] AGGRESSIVE ARTIFACTS...\n")
        for sha256 in report.aggressive_artifacts:
            print(sha256)
    else:
        print("[-] NO AFFRESSIVE ARTIFACTS...\n")


## Main Program
if __name__ == "__main__":
    main_cli()
