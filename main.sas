*libname project "C:\Users\bbsstudent\Desktop\stats_amazing_project";

*Clear result and log windows each time the script is run;
dm "odsresults; clear;";
dm "log; clear;";

*Add title and footer to report;
title "Gym Project";
footnote "@Author: stats_amazing_group @Version: 0.1";

*Import data directly from google forms.
 Debug option is used to view in the log output 
 the http requests to google forms;
filename endpoint url 
"https://docs.google.com/spreadsheets/d/e/2PACX-1vRCuv2f8QfRy9zvI7hX5v1jCs0QcUyP2PAUOfFlBFQTNV-mOBprB1FNDylm6rtdc3urAiVs2_xuusfq/pub?output=csv"
debug;

proc import datafile = endpoint out = dataset dbms = CSV REPLACE;
	getnames = No;
	datarow = 2;
	label var1 = "time";
	label var2 = "gender";
	label var3 = "empl_status";
	label var4 = "age_range";
	label var5 = "has_children";
	label var6 = "car_usage";
	label var7 = "workout_times";
	label var8 = "price";
	label var9 = "installments";
	label var10 = "closeness_home";
	label var11 = "closeness_workplace";
	label var12 = "training_wfriends";
	label var13 = "courses";
	label var14 = "training_machines";
	label var15 = "time_flexibility";
	label var16 = "park_availability";
	label var17 = "amenities";
	label var18 = "personalized_programs";
run;

*SIZE EFFECT PRESENCE VERIFICATION;
*We calculate the mean answer foreach sample and we append it as an additional
 column in the dataset;
data dataset; set dataset;
	avg = mean(of var6-var18);
run;
*We calculate the principal components;
proc princomp data = dataset out = pcs;
	var var6-var18;
run;
*We calculate the correlation between the principal componenets
 and the mean answer column;
proc corr data = pcs;
	var prin: avg;
run;


*SCALING;
data dataset; set dataset; 
	id = _n_; *It adds a numeric id foreach observation;
	min=min(of var6-var18);
	max=max(of var6-var18);
	avg=avg;
	array p1 var6-var18;
	array p2 nvar6-nvar18;
	do over p2;
	if p1 > avg then p2=(p1-avg)/(max-avg);
	if p1 < avg then p2=(p1-avg)/(avg-min);
	if p1 = avg then p2=0;
	if p1 =. then p2 = 0;
	label nvar6 = "car_usage";
	label nvar7 = "workout_times";
	label nvar8 = "price";
	label nvar9 = "installments";
	label nvar10 = "closeness_home";
	label nvar11 = "closeness_workplace";
	label nvar12 = "training_wfriends";
	label nvar13 = "courses";
	label nvar14 = "training_machines";
	label nvar15 = "time_flexibility";
	label nvar16 = "park_availability";
	label nvar17 = "amenities";
	label nvar18 = "personalized_programs";
	end;
run;

*PCA;
*Over the scaled dataset we perform the pca (only on users beliefs);
proc princomp data = dataset out = pcs;
	var nvar8-nvar18;
run;

*CLUSTERING;
proc cluster data = pcs outtree = tree method = ward noprint;
	var prin1-prin6; *We use only the first 6 PCs. (Kaiser -> eigenvalue ~= 1);
	id id;
run;
*We create N clusters. In our case we decided N=4;
proc tree data = tree nclusters = 4 out = cluster;
	id id;
run;

*Print how data is divided in the N clusters;
proc freq data = cluster;
	table cluster; 
run;

*CLUSTER ANALYSIS;
*We merge the cluster dataframe with the dataset containing the answers from 
 the users;
proc sort data = dataset; by id; run;
proc sort data = cluster; by id; run;
proc sort data = pcs; by id; run;
data dataset; merge dataset cluster pcs;
	by id;
run;

*Score plot (observations projected into the principal components) (unused);
title "Score plot";
proc sgplot data = dataset;
	scatter x=prin1 y=prin2 / group=cluster;
run;

*"General" mean for each column;
proc means data = dataset;
	var nvar6-nvar18;
run;

*Means for each cluster;
proc means data = dataset;
	var nvar6-nvar18;
	class cluster; *Like a group by in a query. This generates a mean foreach cluster; 
run;

*[THEORY:Chi-squared test]: We want to check if there is a statistically 
significant difference between the expected frequencies and the observed
frequencies in one or more categories of a contingency table;
*Macro to execute chisq test over each behavioural var;
%macro chisq_vark_cluster;
	%do k=2 %to 5;
		proc freq data = dataset;
			table var&k*cluster / expected chisq;
		run;
	%end;
%mend chisq_vark_cluster;
%chisq_vark_cluster;

*Chisq analysis for confronting each var of each cluster 
(one cluster against all the others);
%macro chisq_vark_clusteri;
	%do i=1 %to 4;
		data clus&i; set dataset;
			cluster&i = .;
			if cluster = &i then cluster&i = 1;
			else cluster&i = 0;
		run;
		%do k=2 %to 5;
			proc freq data = clus&i;
				table var&k*cluster&i / expected chisq;
			run;
		%end;
	%end;
%mend chisq_vark_clusteri;
%chisq_vark_clusteri;


*[THEORY:T-test]: We want to do the following hypothesis test:
is the mean of each variable (columns) of the N different clusters
different from the mean of the "general" population?
This is done via the T-test because this statistical test
is used to check if two means are different
H0: mu_clusx-mu_clusy = 0 (i.e. there is no difference in mean)
H1: mu_clusx-mu_clusy != 0 (i.e. the two means are different);

*To do the t-test comparison we have to generate a fake 
 syntetic "reference cluster" used for the test.;
data syntetic_clus; set dataset;
	cluster = 5; *Sets the cluster column as 5 foreach sample;
run;
*We concatenate the two datasets in one single big ds.;
data syntetic_ds; set dataset syntetic_clus;
run;

%macro ttest_k_cluster;
	ods exclude all; *No print during the execution of the macro;
	%do k=1 %to 4;
		proc ttest data=syntetic_ds plots=none;
			where cluster=&k or cluster=5;
			class cluster;
			var nvar6-nvar18;
			*Saves the result in a table called ttest_Nofthecluster;
			ods output ttests=ttest_&k (where=( method='Satterthwaite') 
			rename=(tvalue=tvalue_clus&k) rename=(probt=pvalue_clus&k));
		run;
	%end;
	ods exclude none;
%mend ttest_k_cluster;
%ttest_k_cluster;

*Merges all the tables of the previously generated t-tests;
data ttest_merged;
	merge ttest_1-ttest_4;
	length descr $20;
	if variable = "nvar6" then descr = "car_usage";
	if variable = "nvar7" then descr = "workout_times";
	if variable = "nvar8" then descr = "price";
	if variable = "nvar9" then descr = "installments";
	if variable = "nvar10" then descr = "closeness_home";
	if variable = "nvar11" then descr = "closeness_workplace";
	if variable = "nvar12" then descr = "training_wfriends";
	if variable = "nvar13" then descr = "courses";
	if variable = "nvar14" then descr = "training_machines";
	if variable = "nvar15" then descr = "time_flexibility";
	if variable = "nvar16" then descr = "park_availability";
	if variable = "nvar17" then descr = "amenities";
	if variable = "nvar18" then descr = "presonalized_programs";
run;

proc print data = ttest_merged;
	var tvalue: pvalue:;
	id descr;
run;

*Plots the t-values foreach cluster to show the characteristics of each cluster.
The plot is generated using only the principal componenets.
The t-tests values can be thought as the "genoma" of a cluster, as them shows
how a specific cluster is different compared to the "general mean"
The principal componenets are then used to "compress" the majority of the variance
simply in two axis that we can plot and evaluate;
proc princomp data = ttest_merged
	out = coord_ttest outstat=coord_ttest_clus;
	var tvalue:;
run;

proc transpose data=coord_ttest_clus out=coord_ttest_clus;
run;

*Loadings plot. Shows  the effect of each t-value on each componenet;
title "Loadings plot";
proc sgplot data = coord_ttest_clus;
	vector x=prin1 y=prin2 / datalabel=_name_;
run;

*Score plot (over the ttest);
title "Score plot";
proc sgplot data = coord_ttest;
	scatter x=prin1 y=prin2 / datalabel=descr;
run;

*Biplot data preparation;
data coord_ttest_clus;
	set coord_ttest_clus;
	rename prin1 = eprin1;
	rename prin2 = eprin2;
	rename prin3 = eprin3;
	rename prin4 = eprin4;
run;

data princomp_merge;
	merge coord_ttest coord_ttest_clus;
run;

*Biplot (unused);
title "Biplot";
proc sgplot data = princomp_merge;
	vector x=eprin1 y=eprin2 / datalabel=_name_;
	scatter x=prin1 y=prin2 / datalabel=descr;
run;

*Export data for smotenc test;
data export; 
	set dataset;
	keep var2-var18 cluster;
run;

proc export data=export
	dbms=csv 
	outfile="/home/u63075170/export/dataset.csv";
run;