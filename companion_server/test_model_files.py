import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

import model_files


def _make_pack(folder, pack):
    folder.mkdir(exist_ok=True)
    for name in model_files.PACKS[pack]["files"]:
        (folder / name).write_bytes(b"x" * 10)


@pytest.fixture
def client(tmp_path, monkeypatch):
    stt, face = tmp_path / "stt", tmp_path / "face"
    _make_pack(stt, "stt")
    _make_pack(face, "face")
    (tmp_path / "secret.txt").write_text("not for the phone")
    (stt / "secret.txt").write_text("not for the phone")
    monkeypatch.setenv("SOLACE_PHONE_STT_DIR", str(stt))
    monkeypatch.setenv("SOLACE_PHONE_FACE_DIR", str(face))
    app = FastAPI()
    app.include_router(model_files.build_router())
    return TestClient(app)


def test_each_pack_has_its_own_manifest_with_sizes(client):
    stt = client.get("/v1/models/stt").json()
    assert stt["model"] == "whisper-base.en"
    assert [f["name"] for f in stt["files"]] == list(model_files.PACKS["stt"]["files"])
    face = client.get("/v1/models/face").json()
    assert face["model"] == "face-v1"
    assert [f["name"] for f in face["files"]] == list(model_files.PACKS["face"]["files"])
    assert all(f["size"] == 10 for f in stt["files"] + face["files"])


def test_each_listed_file_can_be_downloaded_from_its_own_pack(client):
    for pack, spec in model_files.PACKS.items():
        for name in spec["files"]:
            r = client.get(f"/v1/models/{pack}/{name}")
            assert r.status_code == 200 and r.content == b"x" * 10
    # a file of one pack is not served from the other
    assert client.get(f"/v1/models/stt/{model_files.PACKS['face']['files'][0]}").status_code == 404


def test_nothing_outside_the_lists_can_be_reached(client):
    assert client.get("/v1/models/stt/secret.txt").status_code == 404
    assert client.get("/v1/models/stt/..%2Fsecret.txt").status_code == 404
    assert client.get("/v1/models/stt/%2e%2e%2f%2e%2e%2fwindows%2fwin.ini").status_code == 404
    assert client.get("/v1/models/nothing").status_code == 404
    assert client.get("/v1/models/nothing/anything").status_code == 404


def test_a_pack_that_is_not_set_up_is_a_clean_404(monkeypatch):
    monkeypatch.delenv("SOLACE_PHONE_STT_DIR", raising=False)
    monkeypatch.delenv("SOLACE_PHONE_FACE_DIR", raising=False)
    app = FastAPI()
    app.include_router(model_files.build_router())
    c = TestClient(app)
    for pack, spec in model_files.PACKS.items():
        assert c.get(f"/v1/models/{pack}").status_code == 404
        assert c.get(f"/v1/models/{pack}/{spec['files'][0]}").status_code == 404


def test_one_pack_can_be_set_up_without_the_other(tmp_path, monkeypatch):
    _make_pack(tmp_path, "stt")
    monkeypatch.setenv("SOLACE_PHONE_STT_DIR", str(tmp_path))
    monkeypatch.delenv("SOLACE_PHONE_FACE_DIR", raising=False)
    app = FastAPI()
    app.include_router(model_files.build_router())
    c = TestClient(app)
    assert c.get("/v1/models/stt").status_code == 200
    assert c.get("/v1/models/face").status_code == 404


def test_an_incomplete_folder_counts_as_not_set_up(tmp_path, monkeypatch):
    (tmp_path / model_files.PACKS["face"]["files"][0]).write_bytes(b"x")
    monkeypatch.setenv("SOLACE_PHONE_FACE_DIR", str(tmp_path))
    assert model_files.manifest("face") is None
