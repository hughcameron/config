import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from io import StringIO
from pathlib import Path

import typer
from dotenv import dotenv_values, load_dotenv

OP_SESSION_PATH = os.path.expanduser("~/.config/op/.op_session")
OP_LAST_LOGIN = Path(os.path.expanduser("~/.config/op/.op_last_login"))


load_dotenv(OP_SESSION_PATH)


@dataclass
class Credentials:
    username: str = ""
    password: str = ""
    otp: str = ""
    arn: str = ""


def check_session():
    if not OP_LAST_LOGIN.exists():
        typer.echo("Please setup a 1Password session.")
        raise typer.Exit()
    with OP_LAST_LOGIN.open() as f:
        last_login = datetime.fromtimestamp(int(f.read()))
    if last_login + timedelta(minutes=30) < datetime.now():
        typer.echo("Session expired, please login to 1Password.")
        raise typer.Exit()
    typer.echo("1Password Session is valid.")
    return True


def call_op(
    item: str,
    with_otp: bool = False,
    fields: str = ["username", "password"],
) -> tuple:
    if check_session():
        cred = Credentials()
        response = os.popen(
            f"op item get {item} --fields {','.join(fields)} --format json"
        ).read()
        secret = {i["id"]: i["value"] for i in json.loads(response)}
        for k, v in secret.items():
            setattr(cred, k, v)
        if with_otp:
            otp = os.popen(
                f"op item get {item} --field type=otp --format json | jq -r .totp"
            ).read()
            setattr(cred, "otp", otp)
        return cred


def get_creds(credentials_path: Path) -> dict:
    with credentials_path.open() as f:
        accounts = {}
        data = f.read()
        sections = [d for d in data.split("[") if len(d) > 0]
        for a in sections:
            name, details = a.split("]")
            accounts[name] = dict(dotenv_values(stream=StringIO(details)))
    return accounts


def build_creds(accounts: dict) -> str:
    creds = ""
    for name, details in accounts.items():
        creds += f"[{name}]\n"
        for k, v in details.items():
            creds += f"{k} = {v}\n"
        creds += "\n"
    return creds
