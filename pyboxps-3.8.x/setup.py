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
    install_requires=["enum34"],
    entry_points={"console_scripts": ["boxps=pyboxps.boxps:main_cli"]},
    python_requires=">=3.8",
)
