# SiNM

SiNM is a simple network mapper intended to be use in windows operating system.It is written in powershell and it's purpose is to connect to a shared drive or printer in local network.
No GUI. Just plain CLI.

## How to use

You can run `ProgramStart.ps1` in the terminal or you can pack the whole script using [this](https://www.youtube.com/watch?v=_WvIpaYcjaU&ab_channel=JackedProgrammer) (huge shoutout to this guy) youtube video on how to create an `exe` application using [iexpress](https://ss64.com/nt/iexpress.html) in windows.

## How it works

When the script starts, it will automatically create a `mapper_profile.json` in `home` directory. All mapped drive and connected printers will be recorded in this file.

## Limitations

The scripts are only tested in a small network so most of it's functions may need some improvement for bigger uses.

## Note

I know my scripts are lacking, I'm open to ideas. Please let me know. ✌️
