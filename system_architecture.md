Bike System Architecture:

Build a tool for bike riders to help them know the optimal location of dropping off and picking up their bike.
User only cares about the bike experience not the background statistics but those are important to the backend
User sees most optimal bike locations around them and once they choose that, they see the most optimal docking locations around their target location
Need a dataset that has bike ID, dock ID, and time for 5 minute increments for 30 days (including full date). This needs to be simulated and the whole project will be built on top of this.
From this bare bones dataset, we can summarize to get variables like time spent away from a docking station.
Design an R package for optimized bike drop off and pickup
Start by calculating dock flow rates for a given dock at a given time
Use simulated live data and extrapolate dock predictions given dock flow derivation
Yield multiplication of dock predictions based on maintenance/defect predictions
Need to optimize the number of bikes at each station (ensure one station does not have too many or too few and if so we can send a maintenance truck).
For users returning their bike, create incentives (discounted ride) for users to drop off their bike at a suboptimal position for user convenience but an optimal position for dock refill
There will be three test datasets, two built on real data from citi bike and bublr bikes just for docking station location (including geospatial elements like a polygon or coordinates and also the real station ID). The third is completely simulated and discussed in greater depth later. Only pull docking station locations (geospatial data included) pull NO other data other than ID. Use these three test locations to build the simulated datasets that have bike IDs, dock IDS (taken from real data), and time (five minute increments including a simulated real date). The infrastructure should be generalizable to a user inputted location:
Test Location 1: Jersey City (Citi Bike)
Test Location 2: Milwaukee (Bublr)
Test Location 3: Completely simulated including simulated docks (maybe Atlantis)
In terms of the simulated data, consider workday vs. weekday for calculation purposes.
The simulated data is not tracking bike location, if a bike is not at a docking station just list its dock ID as 0. It is assumed to be at some random nearby location and out of the scope of this work.

