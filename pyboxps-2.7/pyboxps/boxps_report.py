import json
import errors
from enum import Enum

####################################################################################################
class Artifact:

    ################################################################################################
    def __init__(self, action_id, artifact_dict):
        self.action_id = action_id
        self.sha256 = artifact_dict["sha256"]
        self.file_type = artifact_dict["fileType"]

# TODO deserialize environment probes
####################################################################################################
class EnvironmentProbe:
    def __init__(self, env_probes_dict):
        pass

####################################################################################################
class Behaviors(Enum):
    network = 1
    file_system = 2
    script_exec = 3
    code_import = 4
    process = 5
    new_object = 6
    file_exec = 7
    memory = 8
    environment_probe = 9
    binary_import = 10

####################################################################################################
class SubBehaviors(Enum):
    file_write = 1
    get_file_info = 2
    change_directory = 3
    file_read = 4
    file_delete = 5
    get_process_info = 6
    kill_process = 7
    pause_process = 8
    import_dotnet_code = 9
    start_process = 10
    probe_os = 11
    probe_language = 12
    probe_date = 13
    upload = 14
    write_to_memory = 15
    new_directory = 16

####################################################################################################
class Action:

    ################################################################################################
    def __init__(self, boxps_config, action_dict):

        # build a list of enum objects for behaviors and subbehaviors
        self.behaviors = [Behaviors[behavior] for behavior in action_dict["Behaviors"]]
        self.sub_behaviors = [SubBehaviors[behavior] for behavior in action_dict["SubBehaviors"]]

        self.actor = action_dict["Actor"]
        self.line = action_dict["Line"]
        self.id = action_dict["Id"]
        self.extra_info = None if action_dict["ExtraInfo"] == "" else action_dict["ExtraInfo"]

        # save the behavior properties in a dict when users want to discover them
        self.behavior_properties = {}
        self.flex_type_properties = boxps_config["BehaviorPropFlexibleTypes"]

        # add the behavior properties as members too for when users know what behavior properties
        # they're looking for
        for behavior_property in action_dict["BehaviorProps"].keys():
            
            # don't save flexible types as members. extra work is required to work with these
            if behavior_property not in self.flex_type_properties:

                property_value = action_dict["BehaviorProps"][behavior_property]
                self.behavior_properties[behavior_property] = property_value
                setattr(self, behavior_property, property_value)

        # just save a dict of the parameters used
        self.parameters = action_dict["Parameters"]


####################################################################################################
class BoxPSReport:

    ################################################################################################
    def __init__(self, boxps_config, report_dict=None, report_path=None):

        if report_dict is not None and report_path is not None:
            raise ValueError("can't give both a report dict and report file path")
        
        if report_dict is None and report_path is None:
            raise ValueError("must give either a report dict or report file path")

        # read the report from a path
        if report_path:
            try:
                with open(report_path, "r") as f:
                    report_dict = json.loads(f.read())
            except Exception as e:
                raise errors.BoxPSReportError("failed to read box-ps report file: " + str(e))

        # deserialize actions into a list sorted by order of execution (action ID)
        self.actions = []
        actions_pool = report_dict["Actions"]

        # basically selection sort the actions list
        while len(actions_pool) != 0:

            action = Action(boxps_config, actions_pool.pop(0))
            action_ndx = 0

            while action_ndx < len(self.actions) and action.id > self.actions[action_ndx]:
                action_ndx += 1

            self.actions.insert(action_ndx, action)

        # confident IOCs 
        network_actions = self.filter_actions(behaviors=[Behaviors.network])
        self.confident_net_iocs = [network_action.uri for network_action in network_actions]

        # aggressive IOCs that include potential IOCs

        # deserialize artifacts, separate out hashes for convenience
        self.artifacts = []
        self.artifact_hashes = []
        for id_to_artifacts in report_dict["Artifacts"].items():
            action_id = int(id_to_artifacts[0])
            for artifact_dict in id_to_artifacts[1]:
                artifact = Artifact(action_id, artifact_dict)
                self.artifact_hashes.append(artifact.sha256.lower())
                self.artifacts.append(artifact)

    ################################################################################################
    @property
    def layers(self):
        # property because this could involve bringing a whole bunch more memory into the process
        # depending on the script. Also may not necessary because it should already be present in
        # out_dir/layers.ps1

        layers = []
        filtered = self.filter_actions(behaviors=[Behaviors.script_exec, Behaviors.code_import])
        for action in filtered:
            if Behaviors.script_exec in action.behaviors and action.script != "":
                layers.append(action.script)
            elif Behaviors.code_import in action.behaviors and action.code != "":
                layers.append(action.code)

        return layers

    ################################################################################################
    def get_action(self, action_id):
        for action in self.actions:
            if action.id == action_id:
                return action
        return None

    ################################################################################################
    def filter_actions(self, behaviors=[], sub_behaviors = [], actors=[], parameters=[]):
        # behaviors is a list of enum
        # actors is a list of substrings of actors
        # parameters is a list of exact parameter matches
        # STILL IN ORDER OF EXECUTION

        filtered = []
        behavior_filter = set(behaviors)
        sub_behavior_filter = set(sub_behaviors)

        for action in self.actions:

            # check for a desired behavior
            if set(action.behaviors) & behavior_filter:
                filtered.append(action)
                continue

            # check for a desired sub_behavior
            if set(action.sub_behaviors) & sub_behavior_filter:
                filtered.append(action)
                continue

            # check for a desired actor
            filtered_actors = [a for a in actors if a in action.actor]
            if filtered_actors:
                filtered.append(action)
                continue

            # check for desired parameters
            filtered_parameters = [p for p in parameters if p in action.parameters.keys()]
            if filtered_parameters:
                filtered.append(action)
                continue

        return filtered

    ################################################################################################
    def actions_by_behavior(self):
        # STILL IN ORDER OF EXECUTION

        split = {}

        for action in self.actions:
            for behavior in action.behaviors:

                if behavior.name not in split:
                    split[behavior.name] = []

                split[behavior.name].append(action)

        return split

    # TODO property method for getting list of certain network IOCs and another for aggressive with 
        # network IOCs that include potential and parameter/layer scraping (make sure this
        # includes all our compensation in maldoc_analyzer.py and make changes to boxps as necessary)
    # TODO do the same thing for file system paths

    # TODO raise reporterrors on whatever failing code would be critical
