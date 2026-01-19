from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("vocab", "0010_personalwordbook"),
    ]

    operations = [
        migrations.AddField(
            model_name="testresult",
            name="assignment_id",
            field=models.CharField(
                blank=True, max_length=50, null=True, verbose_name="과제 ID"
            ),
        ),
    ]
