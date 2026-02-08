#%%

import json
import os
from pathlib import Path

import typer
from dotenv import load_dotenv

import credutil

SSO_ENV = os.path.expanduser("~/scripts/creds/.env")


load_dotenv(SSO_ENV)

AWS_CREDENTIALS = Path(os.path.expanduser("~/.aws/credentials"))
SESSION_NAME = os.getenv("SESSION_NAME")
SESSION_ITEM = os.getenv("SESSION_ITEM")
SESSION_MFA = os.getenv("SESSION_MFA")


accounts = credutil.get_creds(AWS_CREDENTIALS)

app = typer.Typer()


@app.command()
def get_session():

    iam_role = credutil.call_op(SESSION_ITEM)
    user_role = credutil.call_op(
        SESSION_MFA,
        fields=["username", "arn"],
        with_otp=True,
    )

    response = os.popen(
        f"AWS_ACCESS_KEY_ID={iam_role.username} AWS_SECRET_ACCESS_KEY={iam_role.password} aws sts get-session-token --serial-number {user_role.arn} --token-code {user_role.otp}"
    ).read()
    session = json.loads(response)["Credentials"]

    accounts[SESSION_NAME] = {
        "aws_access_key_id": session["AccessKeyId"],
        "aws_secret_access_key": session["SecretAccessKey"],
        "aws_session_token": session["SessionToken"],
        "aws_session_expiration": session["Expiration"],
    }

    with AWS_CREDENTIALS.open("w") as f:
        f.write(credutil.build_creds(accounts))

    typer.echo("AWS session saved.")


#%%


if __name__ == "__main__":
    app()
