from pathlib import Path

from repl.prepare import failure_message, missing_dir


def test_failure_message_unwraps():
    log = ('. save "x", replace\nfile\n    /a/arm_A/Replication/Data/final\n    > /OSS_R.dta could not be opened\n'
           'r(603);\n\nend of do-file\nr(603);\n')
    assert failure_message(log)[0] == "file /a/arm_A/Replication/Data/final/OSS_R.dta could not be opened"
    log2 = ". do \"${do}//make.do\"\nfile /Users/a b/Flexible Work/BG\n    Data/x.do\n    not found\nr(601);\n"
    assert failure_message(log2)[0] == "file /Users/a b/Flexible Work/BG Data/x.do not found"


def test_missing_dir(tmp_path):
    arm = tmp_path / "arm_A"
    (arm / "code").mkdir(parents=True)
    (arm / "Data").mkdir()
    log = f'. save "Datasets/e.dta", replace\n(file Datasets/e.dta not found)\nfile Datasets/e.dta could not be opened\nr(603);\n'
    assert missing_dir(log, arm, arm / "code") == "code/Datasets"
    # after a cd Stata prints the directory
    log2 = f". cd \"{arm}/Data\"\n{arm}/Data\n\n. log using logs/x.log\ndirectory logs not found\nr(601);\n"
    assert missing_dir(log2, arm, arm) == "Data/logs"
    log3 = f"file\n    {arm}/Data/final\n    > /x.dta could not be opened\nr(603);\n"
    assert missing_dir(log3, arm, arm) == "Data/final"
    # existing directory, outside the arm, or reading a missing file: nothing to create
    assert missing_dir(f"file {arm}/Data/x.dta could not be opened\nr(603);\n", arm, arm) is None
    assert missing_dir("file /elsewhere/x/y.dta could not be opened\nr(603);\n", arm, arm) is None
    assert missing_dir("file x.dta not found\nr(601);\n", arm, arm) is None


def test_missing_ado_folder(tmp_path):
    arm = tmp_path / "arm_A"
    (arm / "code").mkdir(parents=True)
    log = (f"    The folder path\n        [{arm}/code/\n        > ado] in\n"
           f"        adopath({arm}/code/ado) does not exist.\nr(99);\n")
    assert missing_dir(log, arm, arm) == "code/ado"


def test_missing_dir_from_echoed_command(tmp_path):
    arm = tmp_path / "arm_A"
    (arm / "Base").mkdir(parents=True)
    log = (f'. global master "{arm}"\n. global pathout "${{master}}/Base/out\n> put"\n\n'
           '  3.         graph export "${pathout}/figures/fig1a.pdf", replace\nunable to save PDF file\nr(691);\n')
    log = log.replace('/out\n> put"', '/output"')
    assert missing_dir(log, arm, arm) == "Base/output/figures"
    assert missing_dir('. graph export "$nowhere/f.pdf"\nunable to save PDF file\nr(691);\n', arm, arm) is None


def test_wrapped_message(tmp_path):
    arm = tmp_path / "arm_A"
    (arm / "pkg").mkdir(parents=True)
    log = f'. cd "${{output_path}}"\nunable to change to {arm}/pk\n> g/output\nr(170);\n'
    assert failure_message(log)[0] == f"unable to change to {arm}/pkg/output"
    assert missing_dir(log, arm, arm) == "pkg/output"


def test_cousin_dirs(tmp_path):
    from repl.prepare import cousin_dirs

    for d in ("P/Baseline Experiments/data", "P/Mechanism Experiments/data", "P/Robust Experiments/data/temp",
              "P/Summary/out"):
        (tmp_path / d).mkdir(parents=True)
    assert cousin_dirs(tmp_path, "P/Baseline Experiments/data/temp") == ["P/Mechanism Experiments/data/temp"]
    assert cousin_dirs(tmp_path, "P/Baseline Experiments/output/figures") == []
