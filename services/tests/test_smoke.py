import sys

import boto3


def test_smoke():
    assert boto3.__version__
    assert sys.version_info >= (3, 13)
