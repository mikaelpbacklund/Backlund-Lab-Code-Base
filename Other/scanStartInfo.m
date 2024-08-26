function scanStartInfo(nSteps,stepDuration,iterations,fudgeFactor)
stepDuration = stepDuration + fudgeFactor;
fprintf('Number of steps in scan: %d\n',nSteps)
fprintf('Each step will take %.2f seconds\n',stepDuration)
fprintf('Total time per iteration will be %d seconds or %.1f minutes\n',round(nSteps*stepDuration),(nSteps*stepDuration)/60)
fprintf('There will be %d iteration(s) for a total time of %.1f minutes\n',iterations,iterations*(nSteps*stepDuration)/60)
end