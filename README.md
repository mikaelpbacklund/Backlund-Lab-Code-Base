# Backlund Lab Primary Function Library
This is the code which was used for the NV experiments for the Backlund group after 2024 (hopefully).

Each instrument is given its own object class which contains the necessary parameters and functions to effectively use it in MatLab.
Additionally, most instruments are part of the instrumentType superclass which contains some useful common functions.
Finally, there is the "experiment" class which links all the various instruments together and enables a scan, reminiscent of the ExperimentEditor app in the previous library.
Currently, full experiments are run using scripts which lay out the experimental parameters then run and display results, but a new app is in development.
