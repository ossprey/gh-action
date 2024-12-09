import argparse
import json
import logging
import sys

from .github_actions_reporter import print_gh_action_errors
from .log import init_logging
from .sbom import create_sbom_from_requirements
from .validate import validate
from .virtualenv import VirtualEnv

logger = logging.getLogger(__name__)


def main():

    parser = argparse.ArgumentParser(description="API URL:")
    parser.add_argument(
        "--url",
        type=str,
        help="The URL to process",
        default="https://api.ossprey.com"
    )
    parser.add_argument(
        "--package",
        type=str,
        help="The package to install",
        default="../example_packages/sample_malpack"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Dry run mode"
    )
    parser.add_argument(
        "--gh",
        action="store_true",
        help="GitHub mode, will attempt to post comments to GitHub"
    )
    parser.add_argument("--verbose", action="store_true", help="Verbose mode")

    # Scanning methods
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument(
        '--pipenv',
        action='store_true',
        help="Install the package to generate the SBOM."
    )
    group.add_argument(
        '--requirements',
        action='store_true',
        help="Path to the requirements file to generate the SBOM."
    )

    args = parser.parse_args()

    init_logging(args.verbose)

    package_name = args.package

    if args.pipenv:
        venv = VirtualEnv()
        venv.enter()

        venv.install_package(package_name)
        requirements_file = venv.create_requirements_file_from_env()

        sbom = create_sbom_from_requirements(requirements_file)

        venv.exit()
    elif args.requirements:
        sbom = create_sbom_from_requirements(package_name + "/requirements.txt")
    else:
        raise Exception("Invalid scanning method")

    if not args.dry_run:
        sbom = validate(args.url, sbom)

    if sbom:
        logger.debug(json.dumps(sbom, indent=4))

        # Process the result
        ret = print_gh_action_errors(sbom, args.package, args.gh)

        if not ret:
            sys.exit(1)
