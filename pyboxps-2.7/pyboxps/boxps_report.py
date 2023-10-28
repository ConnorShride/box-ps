import json
from enum import Enum

import errors


####################################################################################################
class Artifact:

    ################################################################################################
    def __init__(self, action_id, artifact_dict):

        try:

            self.action_id = action_id
            self.sha256 = artifact_dict["sha256"]
            self.file_type = artifact_dict["fileType"]

        except KeyError as e:
            raise errors.BoxPSReportError("bad artifact data in report: " + str(e))

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
    code_create = 11
    task = 12

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
    list_directory_contents = 17
    check_for_file = 18
    get_path = 19
    import_dotnet_binary = 20
    init_code_block = 21
    new_task = 22

####################################################################################################
class Action:

    ################################################################################################
    def __init__(self, boxps_config, action_dict):

        try:

            # build a list of enum objects for behaviors and subbehaviors
            self.behaviors = [Behaviors[behavior] for behavior in action_dict["Behaviors"]]
            self.sub_behaviors = [SubBehaviors[behavior] for behavior in action_dict["SubBehaviors"]]

            self.actor = action_dict["Actor"]
            self.line = action_dict["Line"]
            self.id = action_dict["Id"]
            self.behavior_id = action_dict["BehaviorId"]
            self.extra_info = None if action_dict["ExtraInfo"] == "" else action_dict["ExtraInfo"]

        except KeyError as e:
            raise errors.BoxPSReportError("field in action data not present: " + str(e))

        # save the behavior properties in a dict when users want to discover them
        self.behavior_properties = {}

        try:
            self.flex_type_properties = boxps_config["BehaviorPropFlexibleTypes"]
        except KeyError as e:
            raise errors.BoxPSReportError("field not present in config: " + str(e))

        try:

            # add the behavior properties as members too for when users know what behavior properties
            # they're looking for
            for behavior_property in action_dict["BehaviorProps"].keys():

                property_value = action_dict["BehaviorProps"][behavior_property]
                self.behavior_properties[behavior_property] = property_value

                # don't save flexible types as members. extra work is required to work with these
                if behavior_property not in self.flex_type_properties:
                    setattr(self, behavior_property, property_value)

            # just save a dict of the parameters used
            self.parameters = action_dict["Parameters"]

        except KeyError as e:
            raise errors.BoxPSReportError("field in action data not present: " + str(e))

    ################################################################################################
    def __repr__(self):
        r = ""
        r += "BEHAVIORS: " + str(self.behaviors) + "\n"
        r += "SUB_BEHAVIORS: " + str(self.sub_behaviors) + "\n"
        if (self.extra_info is not None):
            r += "EXTRA_INFO: " + str(self.extra_info) + "\n"
        r += "ACTOR: " + str(self.actor) + "\n"
        r += "LINE: " + str(self.line) + "\n"
        return r

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

        try:
            actions_pool = report_dict["Actions"]
        except KeyError:
            raise errors.BoxPSReportError("no Actions field in report")

        # basically selection sort the actions list
        while len(actions_pool) != 0:

            action = Action(boxps_config, actions_pool.pop(0))
            action_ndx = 0

            while action_ndx < len(self.actions) and action.id > self.actions[action_ndx]:
                action_ndx += 1

            self.actions.insert(action_ndx, action)

        # confident network and file_system IOCs from action behavior properties
        network_actions = self.filter_actions(behaviors=[Behaviors.network])
        file_system_actions = self.filter_actions(behaviors=[Behaviors.file_system])
        self.confident_net_iocs = [network_action.uri for network_action in network_actions]
        self.confident_fs_iocs = []
        for fs_action in file_system_actions:
            if (isinstance(fs_action.paths, list)):
                self.confident_fs_iocs += fs_action.paths

        # aggressive IOCs
        try:
            self.aggressive_net_iocs = report_dict["PotentialIndicators"]["network"]
            self.aggressive_fs_iocs = report_dict["PotentialIndicators"]["file_system"]
            self.aggressive_artifacts = report_dict["PotentialArtifacts"]
        except KeyError as e:
            raise errors.BoxPSReportError("no potential indicators field in report: " + str(e))

        self.artifacts = []
        self.artifact_hashes = []

        # deserialize artifacts, separate out hashes for convenience
        try:

            for id_to_artifacts in report_dict["Artifacts"].items():

                action_id = int(id_to_artifacts[0])

                for artifact_dict in id_to_artifacts[1]:

                    artifact = Artifact(action_id, artifact_dict)
                    self.artifact_hashes.append(artifact.sha256.lower())
                    self.artifacts.append(artifact)

        except KeyError:
            raise errors.BoxPSReportError("no artifacts field in report")

    ################################################################################################
    def __repr__(self):
        r = ""
        for action in self.actions:
            r += "------------\n" + str(action)
        r += "AGGRESSIVE_NET_IOCS: " + str(self.aggressive_net_iocs) + "\n"
        r += "AGGRESSIVE_FS_IOCS: " + str(self.aggressive_fs_iocs) + "\n"
        r += "AGGRESSIVE_ARTIFACTS: " + str(self.aggressive_artifacts) + "\n"
        return r

    ################################################################################################
    @property
    def layers(self):
        """
        Gathers any deobfuscated layers present in the actions. Only includes unique layers gathered
        from actions with the "code_import" or "script_exec" behavior.

        @return (list) unique list of deobfuscated script layers
        """

        layers = []
        filtered = self.filter_actions(behaviors=[Behaviors.script_exec, Behaviors.code_import])

        for action in filtered:

            layer = ""

            if ((Behaviors.script_exec in action.behaviors) and
                hasattr(action, "script") and
                (action.script != "")):
                layer = action.script
            elif Behaviors.code_import in action.behaviors and action.code != "":
                layer = action.code

            if layer and layer not in layers:
                layers.append(layer)

        return layers

    ################################################################################################
    def get_action(self, action_id):
        """
        Gets an action by action ID

        @param action_id (int) action ID

        @return (Action)
        """
        return get_action(self.actions, action_id)

    ################################################################################################
    def filter_actions(self, behaviors=[], sub_behaviors=[], actors=[], parameters=[]):
        """
        Filter the list of actions by behaviors, actors, or parameters used. An action that has any
        of the values you give will be present in the filtered list, which will still be sorted in
        order of their execution in the script.

        @param behaviors (list) of Behavior enum values
        @param sub_behaviors (list) of SubBehavior enum values
        @param actors (list) of substrings to look for in the Actor field of the action
        @param parameters (list) of exact matches on parameter names used in the action

        @return (list) filtered actions
        """
        return filter_actions(self.actions, behaviors, sub_behaviors, actors, parameters)

    ################################################################################################
    def actions_by_behavior(self):
        """
        Gather a dictionary grouping the actions by behavior (not SubBehaviors). The actions in each
        list are still sorted by order of their execution in the script.

        @return (dict) where the keys are behaviors and the values are lists of actions
        """
        return actions_by_behavior(self.actions)


################################################################################################
def get_action(actions, action_id):
    """
    Gets an action by action ID

    @param actions (list) of Action objects
    @param action_id (int) action ID

    @return (Action)
    """

    for action in actions:
        if action.id == action_id:
            return action

    return None

################################################################################################
def filter_actions(actions, behaviors=[], sub_behaviors=[], actors=[], parameters=[]):
    """
    Filter the list of actions by behaviors, actors, or parameters used. An action that has any
    of the values you give will be present in the filtered list, which will still be sorted in
    order of their execution in the script.

    @param actions (list) of Action objects
    @param behaviors (list) of Behavior enum values
    @param sub_behaviors (list) of SubBehavior enum values
    @param actors (list) of substrings to look for in the Actor field of the action
    @param parameters (list) of exact matches on parameter names used in the action

    @return (list) filtered actions
    """

    filtered = []
    behavior_filter = set(behaviors)
    sub_behavior_filter = set(sub_behaviors)

    for action in actions:

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
def actions_by_behavior(actions):
    """
    Gather a dictionary grouping the actions by behavior (not SubBehaviors). The actions in each
    list are still sorted by order of their execution in the script.

    @param actions (list) of Action objects

    @return (dict) where the keys are behaviors and the values are lists of actions
    """

    split = {}

    for action in actions:
        for behavior in action.behaviors:

            if behavior.name not in split:
                split[behavior.name] = []

            split[behavior.name].append(action)

    return split
