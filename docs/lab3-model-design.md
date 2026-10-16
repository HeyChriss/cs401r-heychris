# Lab 3 model design

Track: B, offer-generation RAG.

## Churn model. 

I chose gradient boosting because the retention team has to be told what to do. The dataset is about 10,000 customers and a small set of tabular features, which is enough for a tree model and not a reason to move to a neural net. A neural net might score higher, and we still could not tell an admin which behavior to change to keep churn down. XGBoost gives a gain ranking. On this model that ranking points at days since last purchase and purchase frequency over 180 days, so the action is to reach people who have gone quiet.

Logistic regression would be easy to read, and it would miss the way those two features work together. A customer who bought often and then stopped is not the same case as a customer who was always rare. A linear model needs those combinations built by hand. Boosting finds them.

## What your features bought you. 

Two features carried the signal: days since last purchase (gain 66.6) and purchase frequency over 180 days (gain 62.5). The other nine sit between 9.3 and 19.8. Tenure, channel mix, and the smaller spend totals are decorative next to those two. They do not change what an admin should do.

## LLM system. Why RAG over fine-tuning (Track B), or an agent over a simpler pipeline (Track C)?

I used retrieval because the offer has to follow the written policy, and the policy will change. Fine-tuning would memorize today's loyalty table. The next time a threshold moves, the model would still quote the old number, and there would be no passage to show an admin. Retrieval reads the current benefits for that customer's tier. The category comes from what the customer already buys, because these files are policies and not a product list.

## What you would do differently with 10× the time or data.

With more data I would trust the Platinum slice. It has 21 churners, which is too few to treat its high recall as a finding. With more time I would reject the sentence "points won't expire" in code and generate once more. The prompt already forbids it, and the model wrote it anyway.
