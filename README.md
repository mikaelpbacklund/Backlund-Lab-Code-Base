# Backlund Lab Primary Function Library
This is the code which was used for the NV experiments for the Backlund group between 2020 and 2024.

It uses a central variable - "master" - which contains all the relevant information for each instrument and the experimental parameters.
Master is set as a global variable which allows it to be used for every function. 
This is naturally inefficient to some degree as MatLab does not handle global or persistent variables as efficiently as passing them through as inputs to each function.
Global variables were chosen in order to greatly simplify the code handling, especially for nested or simultaneous functions, at the cost of performance.
Future versions of the code base are being reworked to avoid using global variables through the creation of different experiment classes; this can be viewed on the Object Oriented branch.

Each instrument has its own folder with corresponding functions.
While most functions only use one instrument, there are some - such as PBRun - which use multiple.
Each instrument has an innitialization function which serves to generate the parameters the insturment will use as well as forming the handshake connection with the instrument itself.
  All other functions are specific to the instrument in question.
NDYOV or Nd:YOV stands for neodymium: yttrium orthovanadate which is the laser type used for our experiments. It is a sprout laser from lighthouse photonics*********
NI_DAQ is the data acquisition unit obtained from National Instruments.
Pulse_Blaster is the timing control unit from SpinCore that sends TTL pulses to various other instruments to control their function.
SRS_RF is a microwave generator from stanford research systems that generates precise frequencies between 2 and 4 GHz which are amplified and sent to the NV centers to manipulate their spin.
  The phase of the RF generated can be controlled using TTL pulses from the pulse blaster, allowing for various rotations about the Bloch sphere.
PI_stage is a piezoelectric microscope stage from Physik Instrumente used to move the sample around, especially to focus on individual NV centers.
sCMOS is a camera from Hamamatsu primarily used in other parts of the lab, but sometimes is useful particularly to determine alignment variables.

The other 3 folders are for specific experiments rather than general operation.
Pulse Sequences contain saved data used to recreate a functional pulse sequences; in this way, our lab can easily load previous work to run common experiments.
Sequence Templates contains functions that can be used within the PulseSequenceEditor app to generate sequences systematically.
  This is most useful for experiments that are structurally similar but with unique individual sequences such as XYN-n which is used to detect magnetic fields.
Experiments folder is for saved information from the ExperimentEditor app and is divided into two parts: Data and Setups.
  The data folder contains saved data obtained from past experiments as well as the information needed to parse said data e.g. axes spacing.
  The setups folder contains information that can be used by ExperimentEditor app to recreate specific experimental environments to easily load and run common experiments.

The ExperimentEditor and PulseSequenceEditor apps are the core of how all of these instruments are brought together and used to run our experiments.
The PulseSequenceEditor app is used to turn user-readable pulse sequences to something understood by the instrument, and vice versa.
  It also is capable of loading sequence templates which, as mentioned above, will take a few parameters to systematically generate a new sequence.
ExperimentEditor is by far the largest and most complex individual file, used to control virtually all aspects of an experiment.
  The right half of the app displays the data obtained by the current scan.
  The left half contains all the various experimental parameters for each instrument.
  The app is set up to run scans where certain parameters (stage location, RF frequency, pulse duration, or laser power) are incremented and data is obtained for each point.
  The surrounding options are all for control of various instrument parameters but are not typically changed while the experiment is running unless the experiment is a scan of that parameter.
  
