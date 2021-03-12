import setuptools

setuptools.setup(
    name="pyboxps",
    version="1.0",
    author="Connor Shride",
    author_email="connorshride2@gmail.com",
    description="Python wrapper for running PowerShell sandboxing utility box-ps",
    url="https://github.com/ConnorShride/box-ps",
    classifiers=[
        "Programming Language :: Python :: 2",
        "License :: OSI Approved :: MIT License",
        "Operating System :: Linux",
    ],
    packages=["pyboxps"],
    python_requires="==2.7.*"
)