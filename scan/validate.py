import json
import logging
import requests

logger = logging.getLogger(__name__)


def validate(url, json_bom):

    # Get the url
    url = url + '/ossprey'

    logger.debug(f"JSON Submission: {json.dumps(json_bom)}")

    # Submit bom to API
    headers = {'Content-Type': 'application/json'}
    response = requests.post(url, headers=headers, json=json_bom)
    if response.status_code != 200:
        logger.error("Failed to validate the BOM")
        logger.debug(f"Status code: {response.status_code}")
        logger.debug(f"Response: {response.text}")

        data = response.json()
        if "message" in data:
            logger.error(data["message"])
        return None

    ret = response.json()
    return ret
