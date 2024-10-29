function gbl --wraps='setxkbmap -layout gb' --description 'alias gbl=setxkbmap -layout gb'
  setxkbmap -layout gb $argv; 
end
