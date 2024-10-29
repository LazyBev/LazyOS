function fps --wraps='ps -u lazybev | grep' --description 'alias fps=ps -u lazybev | grep'
  ps -u lazybev | grep $argv
        
end
