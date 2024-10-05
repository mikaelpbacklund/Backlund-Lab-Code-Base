nSuccesses = 0;
for ii = 1:100
    clear s
    s = stage('PI_stage');
    s = connect(s);
    nSuccesses = nSuccesses + 1;
    fprintf('%d successfully connected\n',nSuccesses)
end