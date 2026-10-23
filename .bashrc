#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias NineMensMorris='dotnet run --project ~/Projects/Nine-Mens-Morris/Game' #Run Project
alias reload='clear && echo "" && fastfetch && echo""' #Clear and reload Terminal
alias autosleep='sudo shutdown 120 --no-wall'

#On Start
echo ""
PS1='\[[\e[1;36m\]\u@\h \W\[\e[0m\]]> '
fastfetch
echo ""

