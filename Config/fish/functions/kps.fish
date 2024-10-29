function kps --wraps='kill -9 $(pgrep $argv)' --description 'alias kps=kill -9 $(pgrep $argv)'
  kill -9 $(pgrep $argv) $argv
        
end
