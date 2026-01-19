from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):
    dependencies = [
        ("academy", "0009_assignmenttask_is_replaced"),
    ]

    operations = [
        migrations.CreateModel(
            name="AssignmentSubmissionImage",
            fields=[
                ("id", models.AutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("image", models.ImageField(upload_to="assignments/%Y/%m/%d/", verbose_name="인증샷")),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "submission",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="images",
                        to="academy.assignmentsubmission",
                        verbose_name="과제 인증",
                    ),
                ),
            ],
            options={
                "verbose_name": "과제 인증 이미지",
                "verbose_name_plural": "과제 인증 이미지",
                "ordering": ["created_at"],
            },
        ),
    ]
