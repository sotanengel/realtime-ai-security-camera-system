"""スクリプト群のスモークテスト。

各スクリプトが正常に起動し --help が通ることを確認する。
実際の推論・API呼び出しは行わない。
"""

import subprocess
import sys
from pathlib import Path

SCRIPTS_DIR = Path(__file__).parent.parent / "laptop" / "scripts"


def _run_script(script_name: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(SCRIPTS_DIR / script_name), *args],
        capture_output=True,
        text=True,
    )


def _run_module(module_name: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "-m", module_name, *args],
        capture_output=True,
        text=True,
    )


class TestCollectTrainingSamples:
    def test_help_exits_zero(self) -> None:
        result = _run_script("collect_training_samples.py", "--help")
        assert result.returncode == 0

    def test_help_contains_host_option(self) -> None:
        result = _run_script("collect_training_samples.py", "--help")
        assert "--host" in result.stdout

    def test_help_contains_output_option(self) -> None:
        result = _run_script("collect_training_samples.py", "--help")
        assert "--output" in result.stdout

    def test_help_contains_labels_option(self) -> None:
        result = _run_script("collect_training_samples.py", "--help")
        assert "--labels" in result.stdout


class TestEvaluateModel:
    def test_help_exits_zero(self) -> None:
        result = _run_script("evaluate_model.py", "--help")
        assert result.returncode == 0

    def test_help_contains_model_option(self) -> None:
        result = _run_script("evaluate_model.py", "--help")
        assert "--model" in result.stdout

    def test_help_contains_conf_option(self) -> None:
        result = _run_script("evaluate_model.py", "--help")
        assert "--conf" in result.stdout

    def test_missing_model_exits_nonzero(self) -> None:
        """--model を指定しない場合はエラー終了すること。"""
        result = _run_script("evaluate_model.py")
        assert result.returncode != 0


class TestPackageImport:
    def test_import_package(self) -> None:
        from balcony_guard import __version__

        assert __version__ == "0.1.0"

    def test_collect_module_help(self) -> None:
        result = _run_module("balcony_guard.collect_training_samples", "--help")
        assert result.returncode == 0
        assert "--host" in result.stdout

    def test_evaluate_module_help(self) -> None:
        result = _run_module("balcony_guard.evaluate_model", "--help")
        assert result.returncode == 0
        assert "--model" in result.stdout
