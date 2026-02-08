#%%

import os
from io import StringIO
from pathlib import Path

import typer
from dotenv import dotenv_values, load_dotenv
from playwright.sync_api import Playwright, sync_playwright

import credutil

OP_SESSION_PATH = os.path.expanduser("~/.config/op/.op_session")
OP_LAST_LOGIN = Path(os.path.expanduser("~/.config/op/.op_last_login"))
AWS_CREDENTIALS = Path(os.path.expanduser("~/.aws/credentials"))
SSO_ENV = os.path.expanduser("~/scripts/creds/.env")


load_dotenv(OP_SESSION_PATH)
load_dotenv(SSO_ENV)


SSO_ITEM = os.getenv("SSO_ITEM")
SSO_ACCOUNT_NAME = os.getenv("SSO_ACCOUNT_NAME")

accounts = credutil.get_creds(AWS_CREDENTIALS)


def save_sso(aws_credentials: str):
    _, details = aws_credentials.split("]")
    accounts[SSO_ACCOUNT_NAME] = dict(dotenv_values(stream=StringIO(details)))
    with AWS_CREDENTIALS.open("w") as f:
        f.write(credutil.build_creds(accounts))
    typer.echo("AWS credentials saved.")


def call_sso(
    username: str,
    password: str,
    otp: str,
    playwright: Playwright,
) -> None:
    browser = playwright.chromium.launch()
    context = browser.new_context()

    # Open new page
    page = context.new_page()

    # Go to https://lexer.awsapps.com/start/
    page.goto("https://lexer.awsapps.com/start/")

    # Fill username
    page.locator('[id="awsui-input-0"]').fill(username)

    # Click button:has-text("Next")
    page.locator('button:has-text("Next")').click()

    # Fill input[type="password"]
    page.locator('input[type="password"]').fill(password)

    # Click button:has-text("Sign in")
    page.locator('button:has-text("Sign in")').click()

    # Fill input[type="text"]
    page.locator('input[type="text"]').fill(otp)

    # Click button:has-text("Sign in")
    with page.expect_navigation():
        page.locator('button:has-text("Sign in")').click()

    # Open AWS Accounts
    page.locator('portal-application:has-text("AWS Account")').click()

    # Get Lexer Production Instance
    page.locator('div:has-text("Lexer Production")').nth(3).click()

    # Click text=Command line or programmatic access
    page.locator("text=Command line or programmatic access").click()

    # Click hover-to-copy:has-text("Click to copy this text")
    aws_credentials = page.locator('[id="cli-cred-file-code"]').inner_text()
    aws_credentials = aws_credentials.replace("Click to copy this text", "")
    save_sso(aws_credentials)

    # Close window
    page.locator("//*[contains(@class, 'close')]").click()

    with page.expect_navigation():
        page.locator("text=Sign out").click()

    # ---------------------
    context.close()
    browser.close()


def main():
    typer.echo("Getting credentials from 1Password.")
    cred = credutil.call_op(SSO_ITEM, with_otp=True)
    typer.echo("Getting credentials from AWS SSO.")
    with sync_playwright() as playwright:
        call_sso(cred.username, cred.password, cred.otp, playwright)


if __name__ == "__main__":
    typer.run(main)
